// SVGA framebuffer line fetcher for the native analog output.
//
// In the ET4000 linear framebuffer modes the CPU writes pixels into a framebuffer
// in the HPS DDR3 (base 0x3F80_0000, see main_memory.sv), which the HPS scaler
// reads for HDMI. The FPGA raster carries no pixel data in those modes. This
// module reads each scanline from DDR3 ahead of time into a double line buffer
// and presents the pixel for the dot being displayed: in the 8bpp modes the DAC
// index, which vga.v runs through the palette; in the 16bpp (15/16-bit
// hi-colour) modes the RGB value itself, which vga.v routes past the palette.
//
// Timing contract (all in the VGA clock, which is clk_sys):
//  - ce_pix / not_displaying / vsync come from the same pipeline stage as the
//    DAC index mux in vga.v, so counting displayed dots here aligns with it.
//  - In the 16bpp modes the CRTC is programmed in bytes (two dots per pixel,
//    1280 dots for 640 pixels) and vga.v doubles the dot rate; each pixel is
//    held for two dots and `pix_first` marks the first dot of every pixel.
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
	input             bpp16,           // 1: 16 bits per pixel, else 8
	input       [1:0] fmt16,           // [1] 1=BGR byte order, [0] 1=1555 else 565 (matches FB_FORMAT[4:3])

	// raster timing from vga.v
	input             ce_pix,          // dot clock enable
	input             not_displaying,  // 1 outside the display window (border, blank, sync)
	input             vsync,           // vertical sync (level, active high)
	input             doublescan,      // each framebuffer line is displayed twice
	input      [19:0] start_addr,      // CRTC start address (4-byte units)
	input       [8:0] stride_words,    // CRTC offset register = line stride in 64-bit words
	input       [8:0] width_words,     // displayed width in 64-bit words (8 bytes each)

	output      [7:0] pixel,           // 8bpp: DAC index of the dot being displayed
	output reg [23:0] rgb,             // 16bpp: colour of the dot being displayed
	output reg        pix_first,       // 16bpp: this dot is the first of its pixel (pixel clock enable)

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
// 2 halves x 256 words x 64 bits (up to 2048 bytes per line: 1024 pixels at 16bpp)
reg [63:0] lb [0:511];
reg  [8:0] lb_wr_addr, lb_wr_addr_q;
reg        lb_we;
reg [63:0] lb_wr_data;
always @(posedge clk) if (lb_we) lb[lb_wr_addr_q] <= lb_wr_data;

reg  [8:0] lb_rd_addr;
reg [63:0] lb_rd_q;
always @(posedge clk) lb_rd_q <= lb[lb_rd_addr];

//------------------------------------------------------------------------------ raster side
reg [10:0] x_cnt;       // dot index within the display window
reg        y_par;       // buffer half of the line being displayed
reg  [9:0] vis_line;    // index of the raster line being displayed
reg  [2:0] byte_sel;    // 8bpp: byte of the buffer word for the current dot
reg  [1:0] hw_sel;      // 16bpp: half-word of the buffer word for the pixel being looked up
reg        nd_d, vs_d;
wire [10:0] x_next = not_displaying ? 11'd0 : x_cnt + 1'd1;

// fetch request to the engine (single entry; the engine latches it on accept)
reg        req_valid;
reg  [9:0] req_line;    // framebuffer line
reg        req_buf;     // buffer half
reg        req_line1;   // line 1 still to be requested after line 0 (frame start)
reg        req_taken;   // one-cycle pulse from the engine

wire       vs_start = vsync & ~vs_d;
wire       line_end = ce_pix & not_displaying & ~nd_d;   // display window just closed
wire [9:0] line_n2  = vis_line + 2'd2;

// 16bpp pixel lookahead: pixel p is addressed at the first dot of pixel p-1 (or
// continuously during blanking for pixel 0), so its RAM word is ready well before
// it is latched at the first dot of pixel p. Dots can be a single clock apart at
// the doubled dot rate, pixels never are.
wire [10:0] px_next  = x_next[10:1] + 1'd1;               // pixel after the one starting at x_next
wire        px_start = not_displaying | ~x_next[0];       // the dot starting now is a pixel start

always @(posedge clk) begin
	if (reset | ~enable) begin
		x_cnt <= 0; y_par <= 0; vis_line <= 0; nd_d <= 1; vs_d <= 0;
		req_valid <= 0; req_line1 <= 0; req_line <= 0; req_buf <= 0;
		lb_rd_addr <= 0; byte_sel <= 0; hw_sel <= 0; rgb <= 0; pix_first <= 1;
	end
	else begin
		vs_d <= vsync;

		// engine accepted the current request (handled first: a new request
		// raised in the same cycle below must win)
		if (req_taken) begin
			if (req_line1) begin
				req_valid <= 1;
				req_line  <= 10'd1;
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
			if (bpp16) begin
				pix_first <= px_start;
				if (px_start) begin
					rgb        <= rgb16(lb_rd_q[hw_sel * 16 +: 16]);
					lb_rd_addr <= not_displaying ? {y_par, 8'd0} : {y_par, px_next[9:2]};
					hw_sel     <= not_displaying ? 2'd0 : px_next[1:0];
				end
			end
			else begin
				pix_first  <= 1;
				lb_rd_addr <= {y_par, x_next[10:3]};
				byte_sel   <= x_next[2:0];
			end
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
			req_valid <= 1;
			req_line  <= 0;
			req_buf   <= 0;
			req_line1 <= 1;
		end
	end
end

// 8bpp: the pixel for dot x is byte x[2:0] of buffer word x[10:3]. Address and
// byte select are registered at the previous dot; the RAM read lands one clock
// later, and dots are >= 3 clocks apart.
assign pixel = lb_rd_q[byte_sel * 8 +: 8];

// 16bpp word -> RGB888 (top bits replicated), same interpretation as the HPS scaler
function [23:0] rgb16(input [15:0] w);
	reg [4:0] a, c; reg [5:0] b;
	begin
		if (fmt16[0]) begin a = w[14:10]; b = {w[9:5], w[9]}; c = w[4:0]; end   // 1555
		else          begin a = w[15:11]; b = w[10:5];        c = w[4:0]; end   // 565
		rgb16 = fmt16[1] ? { c, c[4:2], b, b[5:4], a, a[4:2] }                  // BGR
		                 : { a, a[4:2], b, b[5:4], c, c[4:2] };                  // RGB
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
					cur_addr   <= FB_BASE_WORDS + {10'd0, start_addr[19:1]} + req_line * stride_words;
					words_left <= width_words;
					lb_wr_addr <= {req_buf, 8'd0};
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
