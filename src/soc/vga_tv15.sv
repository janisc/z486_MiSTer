/*
 * Copyright (c) 2026, z486_MiSTer native VGA fork
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// 15 kHz TV output stage for the analog port.
//
// The VGA raster stays exactly as the software programmed it (the CRTC, the
// status bits and the HDMI scaler all see the 31.5 kHz picture). This stage
// makes a second raster for a 15 kHz display out of it:
//
//  * every standard VGA line lasts 31.8 us, whichever dot clock the mode uses,
//    so one VGA line played out over the time of two is a 63.5 us line, 15.73 kHz;
//  * one line in two is captured into a line store and replayed with every
//    pixel twice as wide; the other line is dropped. Doublescanned modes
//    (320x200, 320x240, EGA 200-line modes, 40-column text) scan every row twice,
//    so they come out complete: real 240p. The 400/480/350-line modes lose every
//    other row, which is readable and the best a 15 kHz display can show
//    progressively;
//  * the frame rate is the software's (70 or 60 Hz, or 60 Hz when the CRTC pads
//    its frame in TV mode); the picture is progressive: the line phase restarts
//    at every output vsync;
//  * the output vsync is placed by this stage, not by the VGA timing: VGA puts
//    the picture 17 lines after its vsync, a TV needs about 21 (its vertical
//    retrace), so the picture is centred in the TV's visible area from the
//    measured frame length, picture height and picture position;
//  * the horizontal sync and porches are generated here with TV widths
//    (4.7 us sync, picture from 10 us), placed on the input's pixel enable so
//    the active picture is exactly twice the input's;
//  * anything that cannot become a 15 kHz raster (line period outside 31.8 us
//    +/- 5 %, frame outside 400..560 lines, no sync at all) switches the output
//    to a self-timed 15.73 kHz / 60 Hz raster in a fixed colour, so the display
//    never receives an out-of-range signal: SVGA 800x600 and up, UniVBE's 35 Hz
//    modes, and the moment of a mode change all land there.
//
// Input syncs are active-high pulses as delivered by video_cleaner; ce is the
// pixel enable (one per output pixel of the primary raster).
module vga_tv15 #(parameter CLK_RATE = 85000000)
(
	input             clk,
	input             reset,
	input             enable,

	input             ce,
	input       [7:0] r,
	input       [7:0] g,
	input       [7:0] b,
	input             hs,
	input             vs,
	input             de,

	output reg        alt_en,
	output reg  [7:0] alt_r,
	output reg  [7:0] alt_g,
	output reg  [7:0] alt_b,
	output reg        alt_hs,
	output reg        alt_vs,
	output reg        alt_de
);

// ---------------------------------------------------------------- constants
localparam LINE_NOM  = CLK_RATE / 31469;              // 31.469 kHz VGA line, clocks
localparam LINE_LO   = LINE_NOM - LINE_NOM / 20;      // +/- 5 %
localparam LINE_HI   = LINE_NOM + LINE_NOM / 20;
localparam LINES_LO  = 400;                           // lines per frame accepted
localparam LINES_HI  = 560;                           // (449 at 70 Hz, 524/525 at 60 Hz)
localparam HS_CYC    = CLK_RATE / 212766;             // 4.7 us sync
localparam ACT_CYC   = CLK_RATE / 100000;             // picture starts 10 us after sync start
localparam VS_LINES  = 6;                             // output vsync: 6 input lines = 3 output lines
localparam SAFE_LINE = CLK_RATE / 15734;              // self-timed raster: 15.734 kHz
localparam SAFE_ACT1 = ACT_CYC + CLK_RATE / 19231;    // 52 us of picture
localparam SAFE_LINES = 262;                          // 60.05 Hz
localparam SAFE_V0   = 20;                            // picture lines 20..259
localparam SAFE_V1   = 260;
localparam SAFE_VS   = 3;
localparam [23:0] SAFE_RGB = 24'h205030;              // dark green: "alive, mode not shown"
localparam FRAME_MAX = CLK_RATE / 40;                 // 25 ms without a vsync = no picture

// ---------------------------------------------------------------- input edges
reg hs_r, vs_r;
wire hs_rise = hs & ~hs_r;
wire vs_rise = vs & ~vs_r;
always @(posedge clk) begin
	hs_r <= hs;
	vs_r <= vs;
end

// ---------------------------------------------------------------- measurement
// Line period in clocks and lines per frame, judged at every vsync for the
// frame that just ended; two good frames in a row switch the conversion on,
// one bad line, one bad frame or a missing sync switches it off.
reg [15:0] cyc_cnt;
reg [15:0] line_min, line_max;
reg [10:0] frame_lines;
reg [23:0] frame_cyc;
reg  [1:0] ok_cnt;
reg        convert;

wire frame_ok = (line_min >= LINE_LO[15:0]) && (line_max <= LINE_HI[15:0]) &&
                (frame_lines >= LINES_LO[10:0]) && (frame_lines <= LINES_HI[10:0]);

always @(posedge clk) begin
	if (reset) begin
		cyc_cnt     <= 0;
		line_min    <= 16'hFFFF;
		line_max    <= 0;
		frame_lines <= 0;
		frame_cyc   <= 0;
		ok_cnt      <= 0;
		convert     <= 0;
	end
	else begin
		cyc_cnt   <= cyc_cnt + 1'd1;
		frame_cyc <= frame_cyc + 1'd1;
		if (hs_rise) begin
			cyc_cnt <= 0;
			if (cyc_cnt < line_min) line_min <= cyc_cnt;
			if (cyc_cnt > line_max) line_max <= cyc_cnt;
			if (frame_lines != 11'h7FF) frame_lines <= frame_lines + 1'd1;
			// a single line of the wrong length (a mode change in progress) ends the
			// conversion at once; the display never sees more than a line or two of it
			if (cyc_cnt < LINE_LO[15:0] || cyc_cnt > LINE_HI[15:0]) begin
				ok_cnt  <= 0;
				convert <= 0;
			end
		end
		if (vs_rise) begin
			frame_cyc   <= 0;
			frame_lines <= 0;
			line_min    <= 16'hFFFF;
			line_max    <= 0;
			if (frame_ok) begin
				if (ok_cnt != 2'd3) ok_cnt <= ok_cnt + 1'd1;
				if (ok_cnt != 0) convert <= 1;
			end
			else begin
				ok_cnt  <= 0;
				convert <= 0;
			end
		end
		// no line for two line times, or no frame for 25 ms: drop out at once
		if (cyc_cnt > 2 * LINE_HI[15:0] || frame_cyc > FRAME_MAX[23:0]) begin
			ok_cnt  <= 0;
			convert <= 0;
		end
	end
end

// ---------------------------------------------------------------- vertical placement
// Per frame: lines from the input vsync to the first picture line (first_de),
// picture lines (de_lines), lines per frame (F). The output vsync goes
// delay = (first_de - target) mod F input lines after the input vsync, with
// target = 0.539 F - de_lines / 2: the picture centred in the 240 visible lines
// of a 262-line frame after a 21-line vertical retrace, expressed as fractions
// of the frame so a 70 Hz frame on a monitor that takes it is placed the same.
// The delay computed from one frame places the vsync of the next.
reg [10:0] first_de, de_lines, first_de_l, de_lines_l, frame_l;
reg        de_in_line, de_seen;
reg [18:0] mul;
reg [10:0] target;
reg [10:0] dlt, dlt_f;
reg  [2:0] calc;
reg [10:0] delay_reg;
reg [10:0] vs_wait;
reg        armed;
reg        fire;

always @(posedge clk) begin
	fire <= 0;
	if (reset) begin
		first_de   <= 0;
		de_lines   <= 0;
		de_in_line <= 0;
		de_seen    <= 0;
		calc       <= 0;
		delay_reg  <= 0;
		vs_wait    <= 0;
		armed      <= 0;
	end
	else begin
		if (de) de_in_line <= 1;
		if (hs_rise) begin
			de_in_line <= 0;
			if (de_in_line) begin
				de_lines <= de_lines + 1'd1;
				if (~de_seen) begin
					de_seen  <= 1;
					first_de <= frame_lines;
				end
			end
			// the vsync of this frame, from the previous frame's placement
			if (vs_rise) begin
				if (delay_reg == 0) fire <= 1;
				else begin
					vs_wait <= delay_reg - 1'd1;
					armed   <= 1;
				end
			end
			else if (armed) begin
				if (vs_wait == 0) begin
					fire  <= 1;
					armed <= 0;
				end
				else vs_wait <= vs_wait - 1'd1;
			end
		end
		if (vs_rise) begin
			frame_l    <= frame_lines + (hs_rise ? 1'd1 : 1'd0);
			de_lines_l <= de_lines + ((de_in_line & hs_rise) ? 1'd1 : 1'd0);
			first_de_l <= de_seen ? first_de : 11'd0;
			de_lines   <= 0;
			de_seen    <= 0;
			calc       <= 3'd1;
		end
		else case (calc)
			3'd1: begin mul <= frame_l * 8'd138; calc <= 3'd2; end
			3'd2: begin target <= (mul[18:8] > {1'b0, de_lines_l[10:1]}) ? mul[18:8] - {1'b0, de_lines_l[10:1]} : 11'd0; calc <= 3'd3; end
			3'd3: begin dlt <= first_de_l - target; dlt_f <= first_de_l - target + frame_l; calc <= 3'd4; end
			3'd4: begin delay_reg <= (de_lines_l == 0) ? 11'd0 : (first_de_l >= target) ? dlt : dlt_f; calc <= 3'd0; end
			default: ;
		endcase
	end
end

// ---------------------------------------------------------------- line store
// Two lines of 1024 pixels: one being captured, one being replayed.
reg [23:0] lb [0:2047];
reg        cap_phase;      // the line in progress is being captured
reg        cap_buf;        // half of the store written by the capture
reg  [9:0] cap_idx;
reg        rep_buf;        // half handed over to the replay
reg [10:0] cap_len;        // pixels captured in that line
reg        out_start;      // an output line begins now
reg  [2:0] vs_lines;       // output vsync countdown, in input lines
reg        hs_rise_d;      // hs_rise delayed to line up with fire

always @(posedge clk) begin
	out_start <= 0;
	hs_rise_d <= hs_rise;
	if (reset) begin
		cap_phase <= 0;
		cap_buf   <= 0;
		cap_idx   <= 0;
		vs_lines  <= 0;
	end
	else begin
		if (hs_rise_d) begin
			if (cap_phase) begin
				// the line that just ended was captured: replay it from now
				cap_len   <= {1'b0, cap_idx};
				rep_buf   <= cap_buf;
				cap_buf   <= ~cap_buf;
				out_start <= 1;
			end
			cap_idx <= 0;
			// restart the line phase at the output vsync: the line starting now is captured
			cap_phase <= fire ? 1'b1 : ~cap_phase;
			if (fire) vs_lines <= VS_LINES[2:0];
			else if (vs_lines != 0) vs_lines <= vs_lines - 1'd1;
		end
		if (ce & de & cap_phase) begin
			lb[{cap_buf, cap_idx}] <= {r, g, b};
			if (cap_idx != 10'h3FF) cap_idx <= cap_idx + 1'd1;
		end
	end
end

// ---------------------------------------------------------------- replay
// Horizontal sync and picture start are counted in clocks (TV widths whatever
// the mode's dot rate), the pixels advance every second pixel enable.
reg [12:0] out_cyc;
reg        out_run;
reg [10:0] rep_len;
reg        rep_bank;
reg  [9:0] rep_idx;
reg        rep_half;
reg        rep_on;         // pixels are being replayed
reg        rep_done;       // this output line's picture has started (or had nothing to show)
reg        conv_hs_a, conv_de_a;
reg        conv_hs_b, conv_de_b, conv_vs_b;
reg [23:0] lb_q;

always @(posedge clk) begin
	if (reset) begin
		out_run  <= 0;
		out_cyc  <= 0;
		rep_on   <= 0;
		rep_done <= 1;
		rep_idx  <= 0;
		rep_half <= 0;
	end
	else begin
		if (out_start) begin
			out_run  <= 1;
			out_cyc  <= 0;
			rep_len  <= cap_len;
			rep_bank <= rep_buf;
			rep_idx  <= 0;
			rep_half <= 0;
			rep_on   <= 0;
			rep_done <= 0;
		end
		else if (out_run) begin
			if (out_cyc != 13'h1FFF) out_cyc <= out_cyc + 1'd1;
			if (ce) begin
				// the picture starts on the first pixel enable after the porch, so
				// every pixel, the first included, lasts exactly two enables
				if (~rep_done && out_cyc >= ACT_CYC[12:0]) begin
					rep_done <= 1;
					rep_on   <= (rep_len != 0);
				end
				else if (rep_on) begin
					rep_half <= ~rep_half;
					if (rep_half) begin
						rep_idx <= rep_idx + 1'd1;
						if (rep_idx + 1'd1 == rep_len[9:0]) rep_on <= 0;
					end
				end
			end
		end
	end
	// pipeline: address -> data -> output
	lb_q      <= lb[{rep_bank, rep_idx}];
	conv_hs_a <= out_run && (out_cyc < HS_CYC[12:0]);
	conv_de_a <= rep_on && (vs_lines == 0);
	conv_hs_b <= conv_hs_a;
	conv_de_b <= conv_de_a;
	conv_vs_b <= (vs_lines != 0);
end

// ---------------------------------------------------------------- safe raster
reg [12:0] s_cyc;
reg  [8:0] s_line;
always @(posedge clk) begin
	if (reset) begin
		s_cyc  <= 0;
		s_line <= 0;
	end
	else if (s_cyc == SAFE_LINE[12:0] - 1'd1) begin
		s_cyc  <= 0;
		s_line <= (s_line == SAFE_LINES[8:0] - 1'd1) ? 9'd0 : s_line + 1'd1;
	end
	else s_cyc <= s_cyc + 1'd1;
end
wire safe_hs = (s_cyc < HS_CYC[12:0]);
wire safe_vs = (s_line < SAFE_VS[8:0]);
wire safe_de = (s_cyc >= ACT_CYC[12:0]) && (s_cyc < SAFE_ACT1[12:0]) &&
               (s_line >= SAFE_V0[8:0]) && (s_line < SAFE_V1[8:0]);

// ---------------------------------------------------------------- output
always @(posedge clk) begin
	alt_en <= enable;
	if (convert) begin
		alt_hs <= conv_hs_b;
		alt_vs <= conv_vs_b;
		alt_de <= conv_de_b;
		{alt_r, alt_g, alt_b} <= conv_de_b ? lb_q : 24'd0;
	end
	else begin
		alt_hs <= safe_hs;
		alt_vs <= safe_vs;
		alt_de <= safe_de;
		{alt_r, alt_g, alt_b} <= safe_de ? SAFE_RGB : 24'd0;
	end
end

endmodule
