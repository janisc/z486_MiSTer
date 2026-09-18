// Testbench for src/soc/vga_tv15.sv: feeds a VGA-style raster (mode 13h timing,
// then an 800x600 timing) and checks the 15 kHz output: line period, one vsync
// per input frame, picture width in clocks, pixel content, and the safe raster
// for a mode that cannot be converted.
//
//   iverilog -g2012 -o tv15.vvp tb_vga_tv15.sv ../src/soc/vga_tv15.sv && vvp tv15.vvp
`timescale 1ns/1ps
module tb_vga_tv15;

localparam CLK_RATE = 85000000;
reg clk = 0;
always #5 clk = ~clk;

// ---------------------------------------------------------------- raster generator
integer  htotal, hde, hs0, hs1, vtotal, vde, vs0, vs1;
integer  pixclk;
integer  acc = 0;
reg      ce = 0;
integer  x = 0, y = 0;
reg      hs = 0, vs = 0, de = 0;
reg [7:0] r, g, b;
reg      reset = 1;

// ce: fractional divider like the core (pixclk / CLK_RATE per clock)
always @(posedge clk) begin
	ce <= 0;
	if (acc + pixclk >= CLK_RATE) begin
		acc <= acc + pixclk - CLK_RATE;
		ce  <= 1;
	end
	else acc <= acc + pixclk;
end

// raster counters advance on ce; signals registered on ce like video_cleaner
always @(posedge clk) if (ce) begin
	if (x == htotal - 1) begin
		x <= 0;
		y <= (y == vtotal - 1) ? 0 : y + 1;
	end
	else x <= x + 1;
end
wire in_de = (x < hde) && (y < vde);
always @(posedge clk) if (ce) begin
	hs <= (x >= hs0) && (x < hs1);
	if (x == hs0) vs <= (y >= vs0) && (y < vs1);   // vsync changes at hsync start, as video_cleaner does
	de <= in_de;
	r  <= y[7:0];
	g  <= x[7:0];
	b  <= {x[9:8], 6'd0};
end

// ---------------------------------------------------------------- DUT
wire       alt_en, alt_hs, alt_vs, alt_de;
wire [7:0] alt_r, alt_g, alt_b;
vga_tv15 #(.CLK_RATE(CLK_RATE)) dut
(
	.clk(clk), .reset(reset), .enable(1'b1),
	.ce(ce), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
	.alt_en(alt_en), .alt_r(alt_r), .alt_g(alt_g), .alt_b(alt_b),
	.alt_hs(alt_hs), .alt_vs(alt_vs), .alt_de(alt_de)
);

// ---------------------------------------------------------------- monitors
integer errors = 0;
reg  ahs_r = 0, avs_r = 0, ade_r = 0, vs_in_r = 0;
reg [7:0] ag_r;
integer cyc = 0;                 // clocks since last alt_hs rise
integer hs_periods_ok = 0, hs_periods_short = 0, hs_periods_bad = 0;
integer alt_lines = 0;           // alt_hs rises since last alt_vs
integer alt_vs_count = 0, in_vs_count = 0;
integer de_clk = 0;              // clocks of alt_de in the current output line
integer de_lines = 0;            // output lines with picture
integer de_width_min = 1000000, de_width_max = 0;
integer g_steps = 0;             // changes of alt_g inside the picture of one line
integer pix_errors = 0;
integer lines_checked = 0;
integer odd_row_lines = 0;       // picture lines carrying an odd input row (alt_r odd)
integer expected_period;         // 2 x input line in clocks
integer lines_per_frame_last = 0;
integer bad_period_val = 0;
integer debug_prints = 0;
reg     de_seen_this_line = 0;

always @(posedge clk) begin
	ahs_r <= alt_hs; avs_r <= alt_vs; ade_r <= alt_de; vs_in_r <= vs; ag_r <= alt_g;
	cyc <= cyc + 1;
	if (vs & ~vs_in_r) begin
		in_vs_count <= in_vs_count + 1;
		if (debug_prints < 12) begin debug_prints <= debug_prints + 1; $display("  t=%0t input vsync (y=%0d) convert=%0d", $time, y, dut.convert); end
	end
	if (alt_vs & ~avs_r) begin
		alt_vs_count <= alt_vs_count + 1;
		lines_per_frame_last <= alt_lines;
		if (debug_prints < 12) begin debug_prints <= debug_prints + 1; $display("  t=%0t output vsync after %0d lines, convert=%0d", $time, alt_lines, dut.convert); end
	end
	if (alt_hs & ~ahs_r) begin
		alt_lines <= (alt_vs & ~avs_r) ? 1 : alt_lines + 1;
		// classify the period that just ended
		if (cyc > expected_period - 6 && cyc < expected_period + 6) hs_periods_ok <= hs_periods_ok + 1;
		else if (cyc > expected_period / 2 - 6 && cyc < expected_period / 2 + 6) hs_periods_short <= hs_periods_short + 1;
		else begin
			hs_periods_bad <= hs_periods_bad + 1;
			bad_period_val <= cyc;
		end
		cyc <= 1;
	end
	else if (alt_vs & ~avs_r) alt_lines <= 0;

	// picture width and content, alignment-free: measured on the output signals only
	if (alt_de) de_clk <= de_clk + 1;
	if (alt_de & ~ade_r) begin
		g_steps <= 0;
		de_clk  <= 1;
		if (dut.convert && alt_g != 0) begin
			pix_errors <= pix_errors + 1;
			if (pix_errors < 5) $display("FAIL: picture starts with g=%0d (expected 0)", alt_g);
		end
	end
	if (alt_de & ade_r & (alt_g != ag_r) & dut.convert) begin
		g_steps <= g_steps + 1;
		if (alt_g != ((ag_r + 1) % 256)) begin
			pix_errors <= pix_errors + 1;
			if (pix_errors < 5) $display("FAIL: g stepped from %0d to %0d", ag_r, alt_g);
		end
	end
	if (~alt_de & ade_r & dut.convert) begin
		de_lines <= de_lines + 1;
		if (de_clk < de_width_min) de_width_min <= de_clk;
		if (de_clk > de_width_max) de_width_max <= de_clk;
		lines_checked <= lines_checked + 1;
		if (g_steps != hde - 1) begin
			pix_errors <= pix_errors + 1;
			if (pix_errors < 5) $display("FAIL: %0d g steps in a picture line (expected %0d)", g_steps, hde - 1);
		end
		if (alt_r[0]) odd_row_lines <= odd_row_lines + 1;
	end
end

// ---------------------------------------------------------------- test sequence
task set_mode13h;
	begin
		htotal = 800; hde = 640; hs0 = 656; hs1 = 752;
		vtotal = 449; vde = 400; vs0 = 412; vs1 = 414;
		pixclk = 25175000;
	end
endtask
task set_mode_800x600;
	begin
		htotal = 1056; hde = 800; hs0 = 840; hs1 = 968;
		vtotal = 628; vde = 600; vs0 = 601; vs1 = 605;
		pixclk = 36000000;
	end
endtask
task wait_frames(input integer n);
	integer k;
	begin
		for (k = 0; k < n; k = k + 1) @(posedge vs);
	end
endtask
task clear_stats;
	begin
		hs_periods_ok = 0; hs_periods_short = 0; hs_periods_bad = 0;
		alt_vs_count = 0; in_vs_count = 0; de_lines = 0; pix_errors = 0; lines_checked = 0; errors = 0;
		de_width_min = 1000000; de_width_max = 0; odd_row_lines = 0;
	end
endtask

integer exp_de_min, exp_de_max;
initial begin
	set_mode13h;
	expected_period = 2 * 2701;
	repeat (100) @(posedge clk);
	reset = 0;
	wait_frames(4);                         // measurement settles, two good frames
	if (!dut.convert) begin $display("FAIL: conversion not enabled after 4 frames"); errors = errors + 1; end
	@(posedge vs); @(posedge clk); @(posedge clk);
	clear_stats;
	wait_frames(3);
	@(posedge clk); @(posedge clk);
	exp_de_min = (2 * hde) * 3;       // 1280 pixel enables of 3..4 clocks
	exp_de_max = (2 * hde) * 4;
	$display("mode 13h: alt line periods ok=%0d short=%0d bad=%0d (last bad %0d), alt vsyncs=%0d for %0d input frames, picture lines=%0d (odd rows %0d), lines/frame=%0d, de width %0d..%0d clocks, lines checked=%0d pixel errors=%0d",
	         hs_periods_ok, hs_periods_short, hs_periods_bad, bad_period_val, alt_vs_count, in_vs_count, de_lines, odd_row_lines, lines_per_frame_last, de_width_min, de_width_max, lines_checked, pix_errors);
	if (hs_periods_bad != 0) begin $display("FAIL: bad line periods"); errors = errors + 1; end
	if (hs_periods_short > in_vs_count) begin $display("FAIL: more than one short line per frame"); errors = errors + 1; end
	if (alt_vs_count != in_vs_count) begin $display("FAIL: vsync count"); errors = errors + 1; end
	if (de_lines != 200 * in_vs_count) begin $display("FAIL: expected %0d picture lines, got %0d", 200 * in_vs_count, de_lines); errors = errors + 1; end
	if (odd_row_lines != 0) begin $display("FAIL: odd input rows reached the output"); errors = errors + 1; end
	if (de_width_min < exp_de_min || de_width_max > exp_de_max || de_width_max - de_width_min > 8) begin $display("FAIL: picture width"); errors = errors + 1; end
	if (pix_errors != 0) errors = errors + 1;
	if (lines_per_frame_last < 224 || lines_per_frame_last > 226) begin $display("FAIL: lines per frame %0d", lines_per_frame_last); errors = errors + 1; end

	// switch to a mode that cannot be shown: expect the safe raster within a few frames
	set_mode_800x600;
	wait_frames(4);
	if (dut.convert) begin $display("FAIL: conversion still on for 800x600"); errors = errors + 1; end
	expected_period = CLK_RATE / 15734;
	@(posedge alt_vs); @(posedge clk); @(posedge clk);
	clear_stats;
	repeat (3) @(posedge alt_vs);
	@(posedge clk); @(posedge clk);
	$display("800x600: safe raster periods ok=%0d short=%0d bad=%0d (last bad %0d), lines/frame=%0d, alt vsyncs=%0d, convert=%0d, colour r=%0d g=%0d b=%0d",
	         hs_periods_ok, hs_periods_short, hs_periods_bad, bad_period_val, lines_per_frame_last, alt_vs_count, dut.convert, alt_r, alt_g, alt_b);
	if (hs_periods_bad != 0 || hs_periods_short != 0) begin $display("FAIL: safe raster line period"); errors = errors + 1; end
	if (lines_per_frame_last != 262) begin $display("FAIL: safe raster lines per frame %0d", lines_per_frame_last); errors = errors + 1; end
	if (hs_periods_ok != 3 * 262) begin $display("FAIL: safe raster line count %0d", hs_periods_ok); errors = errors + 1; end

	// back to mode 13h: conversion returns
	set_mode13h;
	wait_frames(5);
	if (!dut.convert) begin $display("FAIL: conversion did not return"); errors = errors + 1; end

	if (errors == 0) $display("PASS");
	else $display("FAILED with %0d errors", errors);
	$finish;
end

endmodule
