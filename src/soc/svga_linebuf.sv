// SVGA framebuffer line fetcher for the native analog output.
//
// In the ET4000 linear framebuffer modes the CPU writes pixels into a framebuffer
// in the HPS DDR3 (base 0x3F80_0000, see main_memory.sv), which the HPS scaler
// reads for HDMI. The FPGA raster carries no pixel data in those modes. This
// module reads each scanline from DDR3 ahead of time into a double line buffer
// and presents the pixel for the dot being displayed: in the 8bpp modes the DAC
// index, which vga.v runs through the palette; in the 16bpp (15/16-bit
// hi-colour) and 24bpp modes the RGB value itself, which vga.v routes past the
// palette.
//
// Timing contract (all in the VGA clock, which is clk_sys):
//  - ce_pix / not_displaying / vsync come from the same pipeline stage as the
//    DAC index mux in vga.v, so counting displayed dots here aligns with it.
//  - In the 16bpp modes the CRTC counts one dot per pixel with two bytes per dot
//    (a line is twice as many words as the character count says). The 320-wide
//    modes (VBE 10Dh/10Eh) do it like mode 13h: the sequencer halves the dot
//    clock, so each dot, and each pixel, lasts two clock enables (dotdiv).
//  - In the 24bpp mode the CRTC counts one byte per dot: a 640-pixel line is 1920
//    dots, three per pixel (vga.v runs the dot clock at 3x so the line rate stays
//    31.5 kHz; dots can then be a single clock apart, pixels never are). The
//    three bytes of a pixel are read at its first dot with a two-cycle, two-word
//    read (a pixel can straddle two buffer words); `pix_ce` marks that dot.
//  - At the end of each displayed line n the line for raster line n+2 is
//    fetched into the buffer half that line n just used; line n+1 is already in
//    the other half. Lines 0 and 1 are fetched at vsync. A fetch has a full
//    line time to complete.
//  - The DDR3 port is shared with main_memory's framebuffer write/read port;
//    `ddr_busy` is asserted by the arbiter while that port has work in flight,
//    and `owner` tells the arbiter this module holds the bus.
module svga_linebuf
(
	input             clk,
	input             reset,
	input             enable,          // framebuffer mode with native output selected
	input       [1:0] bpp,             // 0: 8 bits per pixel, 1: 16, 2: 24
	input       [1:0] fmt16,           // [1] 1=BGR byte order, [0] 1=1555 else 565 (matches FB_FORMAT[4:3])

	// raster timing from vga.v
	input             ce_pix,          // dot clock enable
	input             not_displaying,  // 1 outside the display window (border, blank, sync)
	input             vsync,           // vertical sync (level, active high)
	input             doublescan,      // each framebuffer line is displayed twice
	input             dotdiv,          // sequencer dot clock divided by two: a dot lasts two ce_pix
	input      [19:0] start_addr,      // CRTC start address (4-byte units)
	input       [8:0] stride_words,    // CRTC offset register = line stride in 64-bit words
	input       [8:0] width_words,     // displayed width in 64-bit words (8 bytes each)

	output      [7:0] pixel,           // 8bpp: DAC index of the dot being displayed
	output     [23:0] rgb,             // 16/24bpp: colour of the dot being displayed
	output reg        pix_ce,          // 24bpp: a new pixel starts on this dot (pixel clock enable); else 1

	// DDR3 read master (64-bit words, address in words)
	output reg [28:0] ddr_addr,
	output reg        ddr_rd,
	output reg  [7:0] ddr_burstcnt,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	input             ddr_busy,        // DDR busy, or the other master has work in flight
	output            owner            // this module holds the bus
);

localparam [28:0] FB_BASE_WORDS = 29'h07F0_0000; // 0x3F80_0000 >> 3

//------------------------------------------------------------------------------ line buffer
// 2 halves x 512 words x 64 bits (up to 4096 bytes per line: 1024 pixels at 24bpp)
reg [63:0] lb [0:1023];
reg  [9:0] lb_wr_addr, lb_wr_addr_q;
reg        lb_we;
reg [63:0] lb_wr_data;
always @(posedge clk) if (lb_we) lb[lb_wr_addr_q] <= lb_wr_data;

reg  [9:0] lb_rd_addr;
reg [63:0] lb_rd_q;
always @(posedge clk) lb_rd_q <= lb[lb_rd_addr];

// 24bpp: second word of a straddling pixel, read the cycle after the first
// (sequenced in the raster block below)
reg        rd2_pending;   // issue the read of word+1 next cycle
reg        rd2_capture;   // lb_rd_q holds the first word now: keep it
reg        rd2_done;      // both words are in: assemble the colour
reg [63:0] q0;            // first word of the pixel
reg [23:0] rgb24;         // assembled 24bpp colour, stable for the whole pixel
reg  [2:0] b24_sel;       // byte offset of the pixel in q0
// bytes 3p..3p+2 of {word+1, word}: memory order B,G,R (VESA) when the format
// says BGR, R,G,B otherwise
wire [127:0] w24 = {lb_rd_q, q0};
wire  [23:0] p24 = w24[b24_sel * 8 +: 24];
reg  [9:0] px24;          // 24bpp: pixel shown at the current dot
reg  [1:0] ph24;          // 24bpp: (2 * dot) mod 3, the 2:3 pixel/dot phase

//------------------------------------------------------------------------------ raster side
reg [10:0] x_cnt;       // dot index within the display window
reg        y_par;       // buffer half of the line being displayed
reg  [9:0] vis_line;    // index of the raster line being displayed
reg  [2:0] byte_sel;    // 8bpp: byte of the buffer word for the current dot
reg  [1:0] hw_sel;      // 16bpp: half-word of the buffer word for the current dot
wire        px24_adv = (ph24 == 2'd0);                            // 24bpp: this dot starts a new pixel
wire  [9:0] px24_new = not_displaying ? 10'd0 : px24 + 1'd1;      // (blanking prefetches pixel 0)
wire [11:0] b24_off  = {px24_new, 1'b0} + px24_new;              // 24bpp: byte offset of that pixel (3p)
reg        nd_d, vs_d;
wire  [9:0] pitch_words = (bpp == 2'd1 && dotdiv) ? {stride_words, 1'b0} : {1'b0, stride_words};
reg         dot_ph;                                              // dotdiv: second clock of the dot
wire        dot_adv = ~dotdiv | dot_ph;                          // this ce_pix starts a new dot
wire [10:0] x_next = not_displaying ? 11'd0 : dot_adv ? x_cnt + 1'd1 : x_cnt;

// fetch request to the engine (single entry; the engine latches it on accept)
reg        req_valid;
reg  [9:0] req_line;    // framebuffer line
reg        req_buf;     // buffer half
reg        req_line1;   // line 1 still to be requested after line 0 (frame start)
reg        req_taken;   // one-cycle pulse from the engine
reg [19:0] start_lat;   // start address latched at vertical retrace start, as the VGA CRTC does:
                        // a display-start change (page flip) takes effect on the next frame only

wire       vs_start = vsync & ~vs_d;
wire       line_end = ce_pix & not_displaying & ~nd_d;   // display window just closed
wire [9:0] line_n2  = vis_line + 2'd2;

always @(posedge clk) begin
	if (reset | ~enable) begin
		x_cnt <= 0; y_par <= 0; vis_line <= 0; nd_d <= 1; vs_d <= 0; dot_ph <= 0;
		req_valid <= 0; req_line1 <= 0; req_line <= 0; req_buf <= 0; start_lat <= 0;
		lb_rd_addr <= 0; byte_sel <= 0; hw_sel <= 0; b24_sel <= 0;
		rd2_pending <= 0; rd2_capture <= 0; rd2_done <= 0; rgb24 <= 0; px24 <= 10'h3FF; ph24 <= 0; pix_ce <= 1;
	end
	else begin
		vs_d <= vsync;

		// 24bpp second-word read: the dot's ce (below) sets the first address and
		// rd2_pending; the next cycle addresses word+1, the cycle after keeps the
		// first word in q0 while lb_rd_q delivers the second
		rd2_pending <= 0;
		rd2_capture <= rd2_pending;
		rd2_done    <= rd2_capture;
		if (rd2_pending) lb_rd_addr <= lb_rd_addr + 1'd1;
		if (rd2_capture) q0 <= lb_rd_q;
		// registered once per pixel: at the doubled/tripled dot rate the next pixel's
		// first word can land in lb_rd_q while this pixel is still being sampled
		if (rd2_done) rgb24 <= fmt16[1] ? {p24[23:16], p24[15:8], p24[7:0]} : {p24[7:0], p24[15:8], p24[23:16]};

		// engine accepted the current request (handled first: a new request
		// raised in the same cycle below must win)
		if (req_taken) begin
			if (req_line1) begin
				req_valid <= 1;
				req_line  <= doublescan ? 10'd0 : 10'd1;
				req_buf   <= 1;
				req_line1 <= 0;
			end
			else begin
				req_valid <= 0;
			end
		end

		if (ce_pix) begin
			nd_d       <= not_displaying;
			x_cnt      <= x_next;
			dot_ph     <= ~dot_ph;                            // free-running like the VGA's own
			                                                  // divided dot clock: the pixel clock
			                                                  // enable must keep running in blanking
			case (bpp)
				2'd1: begin                                   // 16bpp: 4 pixels per word
					lb_rd_addr <= {y_par, x_next[10:2]};
					hw_sel     <= x_next[1:0];
					pix_ce     <= dot_adv;                        // one pixel per dot
				end
				2'd2: begin                                   // 24bpp: 3 dots per pixel
					// the 3-dot phase runs through blanking too (pixel clock enable every
					// third dot for the framework); blanking parks the pixel at -1 and
					// prefetches pixel 0 so the first displayed dot starts on pixel 0
					ph24   <= (ph24 == 2'd2) ? 2'd0 : ph24 + 1'd1;
					px24   <= not_displaying ? 10'h3FF : px24_adv ? px24_new : px24;
					pix_ce <= (ph24 == 2'd0);
					if (px24_adv) begin                       // word of byte 3p, then the next one
						lb_rd_addr  <= {y_par, b24_off[11:3]};
						b24_sel     <= b24_off[2:0];
						rd2_pending <= 1;
					end
				end
				default: begin                                // 8bpp: 8 pixels per word
					lb_rd_addr <= {y_par, 1'b0, x_next[10:3]};
					byte_sel   <= x_next[2:0];
				end
			endcase
			if (bpp == 2'd0) pix_ce <= dot_adv;
			if (line_end) begin
				// line n done: fetch raster line n+2 into the half line n used
				req_valid <= 1;
				req_line  <= doublescan ? {1'b0, line_n2[9:1]} : line_n2;
				req_buf   <= y_par;
				y_par     <= ~y_par;
				vis_line  <= vis_line + 1'd1;
			end
		end

		if (vs_start) begin
			// frame start: line 0 -> half 0 now, line 1 -> half 1 right after
			vis_line  <= 0;
			y_par     <= 0;
			start_lat <= start_addr;
			req_valid <= 1;
			req_line  <= 0;
			req_buf   <= 0;
			req_line1 <= 1;
		end
	end
end

// The pixel for dot x is byte x[2:0] of buffer word x[10:3] (8bpp) or half-word
// x[1:0] of word x[9:2] (16bpp). Address and select are registered at the
// previous dot; the RAM read lands one clock later, and dots are >= 3 clocks apart.
assign pixel = lb_rd_q[byte_sel * 8 +: 8];
assign rgb   = (bpp == 2'd2) ? rgb24 : rgb16(lb_rd_q[hw_sel * 16 +: 16]);

// 16bpp word -> RGB888 (top bits replicated), same interpretation as the HPS scaler
function [23:0] rgb16(input [15:0] w);
	reg [4:0] a, c; reg [5:0] b;
	begin
		if (fmt16[0]) begin a = w[14:10]; b = {w[9:5], w[9]}; c = w[4:0]; end   // 1555
		else          begin a = w[15:11]; b = w[10:5];        c = w[4:0]; end   // 565
		// the scaler byte-swaps DDR3 words, so its "BGR" (FB_FORMAT[4]=1) shows the
		// low field as red; mirror that so both outputs agree
		rgb16 = fmt16[1] ? { a, a[4:2], b, b[5:4], c, c[4:2] }
		                 : { c, c[4:2], b, b[5:4], a, a[4:2] };
	end
endfunction

//------------------------------------------------------------------------------ fetch engine
localparam S_IDLE = 2'd0, S_ISSUE = 2'd1, S_DATA = 2'd2;
reg  [1:0] state;
reg [28:0] cur_addr;
reg  [8:0] words_left;
reg  [7:0] burst_left;

assign owner = (state != S_IDLE);

always @(posedge clk) begin
	lb_we     <= 0;
	req_taken <= 0;
	if (reset | ~enable) begin
		state <= S_IDLE; ddr_rd <= 0; ddr_burstcnt <= 8'd8; ddr_addr <= 0;
		words_left <= 0; burst_left <= 0; cur_addr <= 0; lb_wr_addr <= 0; lb_wr_addr_q <= 0;
	end
	else begin
		case (state)
			S_IDLE: begin
				ddr_rd <= 0;
				if (req_valid & ~req_taken & ~ddr_busy) begin
					req_taken  <= 1;
					// row pitch: the offset register in 8-byte units, doubled in the 16bpp modes
					// with the halved dot clock (320x200 hi-colour: measured against the BIOS's
					// own display-start arithmetic, 640 bytes per row with offset = 40)
					cur_addr   <= FB_BASE_WORDS + {10'd0, start_lat[19:1]} + req_line * pitch_words;
					// 16bpp: the CRTC counts pixels, a line is twice the words; 8/24bpp: it
					// counts bytes, width_words is already the line length
					words_left <= (bpp == 2'd1) ? {width_words[7:0], 1'b0} : width_words;
					lb_wr_addr <= {req_buf, 9'd0};
					state      <= S_ISSUE;
				end
			end
			S_ISSUE: begin
				// one burst of up to 8 words; hold rd until the DDR accepts it
				if (words_left == 0) begin
					ddr_rd <= 0;
					state  <= S_IDLE;
				end
				else if (~ddr_rd) begin
					ddr_addr     <= cur_addr;
					ddr_burstcnt <= (words_left >= 9'd8) ? 8'd8 : words_left[7:0];
					burst_left   <= (words_left >= 9'd8) ? 8'd8 : words_left[7:0];
					ddr_rd       <= 1;
				end
				else if (~ddr_busy) begin
					ddr_rd     <= 0;
					cur_addr   <= cur_addr + {21'd0, ddr_burstcnt};
					words_left <= words_left - {1'b0, ddr_burstcnt};
					state      <= S_DATA;
				end
			end
			S_DATA: begin
				if (ddr_dout_ready) begin
					lb_we        <= 1;
					lb_wr_data   <= ddr_dout;
					lb_wr_addr_q <= lb_wr_addr;
					lb_wr_addr   <= lb_wr_addr + 1'd1;
					burst_left   <= burst_left - 1'd1;
					if (burst_left == 8'd1) state <= S_ISSUE;
				end
			end
			default: state <= S_IDLE;
		endcase
	end
end

endmodule
