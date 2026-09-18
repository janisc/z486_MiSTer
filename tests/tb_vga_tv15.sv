// Testbench for src/soc/vga_tv15.sv: feeds VGA-style rasters and checks the 15 kHz output.
//  1. mode 13h timing (449 rows, doublescanned): line period, one short line per frame, 200
//     picture lines, exact width and pixel order, picture placed ~21 lines below the output
//     vsync, vsync starting together with an output line;
//  2. the CRTC's padded 524-row frame: 262 lines, no short line, picture at ~41 lines;
//  3. interlace: a 400-row non-doublescanned raster as two fields (row parity alternates);
//  4. an 800x600 raster: the safe raster, 262 lines;
//  5. the H and V position offsets.
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
reg      doublescan = 1;
reg [1:0] hpos = 0, vpos = 0;
reg      ilace_en = 0;

always @(posedge clk) begin
	ce <= 0;
	if (acc + pixclk >= CLK_RATE) begin
		acc <= acc + pixclk - CLK_RATE;
		ce  <= 1;
	end
	else acc <= acc + pixclk;
end
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
	if (x == hs0) vs <= (y >= vs0) && (y < vs1);
	de <= in_de;
	r  <= doublescan ? (y / 2) : y;      // row number: with doublescan both scans carry the same row
	g  <= x[7:0];
	b  <= {x[9:8], 6'd0};
end

// ---------------------------------------------------------------- DUT
wire       alt_en, alt_hs, alt_vs, alt_de;
wire [7:0] alt_r, alt_g, alt_b;
vga_tv15 #(.CLK_RATE(CLK_RATE)) dut
(
	.clk(clk), .reset(reset), .enable(1'b1), .hpos(hpos), .vpos(vpos), .ilace_en(ilace_en), .doublescan(doublescan),
	.ce(ce), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de),
	.alt_en(alt_en), .alt_r(alt_r), .alt_g(alt_g), .alt_b(alt_b),
	.alt_hs(alt_hs), .alt_vs(alt_vs), .alt_de(alt_de)
);

// ---------------------------------------------------------------- monitors
integer errors = 0;
reg  ahs_r = 0, avs_r = 0, ade_r = 0, vs_in_r = 0;
reg [7:0] ag_r;
integer cyc = 0;
integer hs_periods_ok = 0, hs_periods_short = 0, hs_periods_bad = 0, bad_period_val = 0;
integer alt_lines = 0, lines_per_frame_last = 0, lines_since_ovs = 0;
integer alt_vs_count = 0, in_vs_count = 0;
integer de_clk = 0, de_lines = 0, de_width_min = 1000000, de_width_max = 0;
integer g_steps = 0, pix_errors = 0, lines_checked = 0, odd_row_lines = 0;
integer expected_period;
integer pic_top = -1, pic_top_last = -1;
integer vs_hs_ofs = 0, vs_hs_ofs_last = -1;    // clocks from the alt_vs rise to the next alt_hs rise
integer de_ofs_last = -1;                      // clocks from the alt_hs rise to the alt_de rise
integer first_row = -1, first_row_last = -1;   // alt_r of the first picture line of the frame
integer parity_changes = 0, prev_first_row = -1;
reg     vs_pending_ofs = 0;

always @(posedge clk) begin
	ahs_r <= alt_hs; avs_r <= alt_vs; ade_r <= alt_de; vs_in_r <= vs; ag_r <= alt_g;
	cyc <= cyc + 1;
	if (vs & ~vs_in_r) in_vs_count <= in_vs_count + 1;
	if (alt_vs & ~avs_r) begin
		alt_vs_count <= alt_vs_count + 1;
		lines_per_frame_last <= alt_lines;
		lines_since_ovs <= 0;
		pic_top <= -1;
		vs_pending_ofs <= 1;
		vs_hs_ofs <= 0;
		if (first_row >= 0) begin
			if (prev_first_row >= 0 && (first_row % 2) != (prev_first_row % 2)) parity_changes <= parity_changes + 1;
			prev_first_row <= first_row;
			first_row_last <= first_row;
		end
		first_row <= -1;
	end
	else if (vs_pending_ofs) vs_hs_ofs <= vs_hs_ofs + 1;
	if (alt_hs & ~ahs_r) begin
		alt_lines <= (alt_vs & ~avs_r) ? 1 : alt_lines + 1;
		lines_since_ovs <= (alt_vs & ~avs_r) ? 1 : lines_since_ovs + 1;
		if (vs_pending_ofs || (alt_vs & ~avs_r)) begin vs_pending_ofs <= 0; vs_hs_ofs_last <= (alt_vs & ~avs_r) ? 0 : vs_hs_ofs; end
		if (cyc > expected_period - 6 && cyc < expected_period + 6) hs_periods_ok <= hs_periods_ok + 1;
		else if (cyc > expected_period / 2 - 6 && cyc < expected_period / 2 + 6) hs_periods_short <= hs_periods_short + 1;
		else begin hs_periods_bad <= hs_periods_bad + 1; bad_period_val <= cyc; end
		cyc <= 1;
	end
	else if (alt_vs & ~avs_r) alt_lines <= 0;

	if (alt_de) de_clk <= de_clk + 1;
	if (alt_de & ~ade_r) begin
		g_steps <= 0;
		de_clk  <= 1;
		de_ofs_last <= cyc;
		if (pic_top < 0) begin pic_top <= lines_since_ovs; pic_top_last <= lines_since_ovs; end
		if (first_row < 0) first_row <= alt_r;
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

// ---------------------------------------------------------------- helpers
task set_mode13h;      begin htotal = 800; hde = 640; hs0 = 656; hs1 = 752; vtotal = 449; vde = 400; vs0 = 412; vs1 = 414; pixclk = 25175000; doublescan = 1; end endtask
task set_mode_800x600; begin htotal = 1056; hde = 800; hs0 = 840; hs1 = 968; vtotal = 628; vde = 600; vs0 = 601; vs1 = 605; pixclk = 36000000; doublescan = 0; end endtask
task wait_frames(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) @(posedge vs); end endtask
task clear_stats;
	begin
		hs_periods_ok = 0; hs_periods_short = 0; hs_periods_bad = 0; alt_vs_count = 0; in_vs_count = 0; de_lines = 0;
		pix_errors = 0; lines_checked = 0; errors = 0; de_width_min = 1000000; de_width_max = 0; odd_row_lines = 0;
		parity_changes = 0; prev_first_row = -1;
	end
endtask
integer total_errors = 0;
task fail(input [255:0] what); begin $display("FAIL: %0s", what); errors = errors + 1; end endtask
task phase_done(input [255:0] name);
	begin
		if (errors == 0) $display("%0s: ok", name); else $display("%0s: %0d errors", name, errors);
		total_errors = total_errors + errors;
	end
endtask

// ---------------------------------------------------------------- test sequence
initial begin
	// ---- 1. mode 13h
	set_mode13h; expected_period = 2 * 2701;
	repeat (100) @(posedge clk); reset = 0;
	wait_frames(5);
	if (!dut.convert) fail("conversion not enabled");
	@(posedge vs); @(posedge clk); @(posedge clk); clear_stats;
	wait_frames(3); @(posedge clk); @(posedge clk);
	$display("mode 13h: periods ok=%0d short=%0d bad=%0d, vsyncs %0d/%0d, picture lines %0d, lines/frame %0d, de width %0d..%0d, top %0d, vs->hs %0d clk, de offset %0d clk, pixel errors %0d",
	         hs_periods_ok, hs_periods_short, hs_periods_bad, alt_vs_count, in_vs_count, de_lines, lines_per_frame_last, de_width_min, de_width_max, pic_top_last, vs_hs_ofs_last, de_ofs_last, pix_errors);
	if (hs_periods_bad != 0) fail("bad line periods");
	if (hs_periods_short > in_vs_count) fail("more than one short line per frame");
	if (alt_vs_count != in_vs_count) fail("vsync count");
	if (de_lines != 200 * in_vs_count) fail("picture lines");
	if (de_width_min < 2 * hde * 3 || de_width_max > 2 * hde * 4 || de_width_max - de_width_min > 8) fail("picture width");
	if (pix_errors != 0) fail("pixels");
	if (lines_per_frame_last < 224 || lines_per_frame_last > 226) fail("lines per frame");
	if (pic_top_last < 20 || pic_top_last > 25) fail("picture placement");
	if (vs_hs_ofs_last > 12) fail("vsync not at an output line start");
	if (de_ofs_last < 850 - 8 || de_ofs_last > 850 + 40) fail("picture start offset");
	phase_done("1 mode 13h");

	// ---- 2. padded 524-row frame
	vtotal = 524; clear_stats;
	wait_frames(4); @(posedge vs); @(posedge clk); @(posedge clk); clear_stats;
	wait_frames(3); @(posedge clk); @(posedge clk);
	$display("524 rows: periods ok=%0d short=%0d bad=%0d, vsyncs %0d/%0d, picture lines %0d, lines/frame %0d, top %0d, vs->hs %0d clk, pixel errors %0d",
	         hs_periods_ok, hs_periods_short, hs_periods_bad, alt_vs_count, in_vs_count, de_lines, lines_per_frame_last, pic_top_last, vs_hs_ofs_last, pix_errors);
	if (hs_periods_bad != 0 || hs_periods_short != 0) fail("524-row line periods");
	if (lines_per_frame_last != 262) fail("524-row lines per frame");
	if (de_lines != 200 * in_vs_count || alt_vs_count != in_vs_count) fail("524-row picture/vsync count");
	if (pic_top_last < 40 || pic_top_last > 44) fail("524-row placement");
	if (vs_hs_ofs_last > 12) fail("524-row vsync alignment");
	if (pix_errors != 0) fail("524-row pixels");
	phase_done("2 padded frame");

	// ---- 3. interlace on a 400-row progressive raster (525-row frame: 262.5 lines per field)
	doublescan = 0; ilace_en = 1; vtotal = 525; clear_stats;   // the CRTC keeps the frame odd for interlace
	wait_frames(5); @(posedge vs); @(posedge clk); @(posedge clk); clear_stats;
	wait_frames(4); @(posedge clk); @(posedge clk);
	$display("interlace: periods ok=%0d short=%0d bad=%0d (last bad %0d), vsyncs %0d/%0d, picture lines %0d, lines/frame %0d, parity changes %0d of %0d frames, last first row %0d, vs->hs %0d clk, pixel errors %0d",
	         hs_periods_ok, hs_periods_short, hs_periods_bad, bad_period_val, alt_vs_count, in_vs_count, de_lines, lines_per_frame_last, parity_changes, alt_vs_count, first_row_last, vs_hs_ofs_last, pix_errors);
	if (hs_periods_bad != 0) fail("interlace line periods");
	if (hs_periods_short != 0) fail("interlace: short lines");
	if (de_lines != 200 * in_vs_count) fail("interlace picture lines");
	if (parity_changes < alt_vs_count - 1) fail("interlace: row parity does not alternate every field");
	if (pix_errors != 0) fail("interlace pixels");
	phase_done("3 interlace");
	ilace_en = 0; doublescan = 1;

	// ---- 4. 800x600: safe raster
	set_mode_800x600;
	wait_frames(3);
	if (dut.convert) fail("conversion still on for 800x600");
	expected_period = CLK_RATE / 15734;
	@(posedge alt_vs); @(posedge clk); @(posedge clk); clear_stats;
	repeat (2) @(posedge alt_vs); @(posedge clk); @(posedge clk);
	$display("800x600: safe periods ok=%0d short=%0d bad=%0d, lines/frame %0d, convert %0d", hs_periods_ok, hs_periods_short, hs_periods_bad, lines_per_frame_last, dut.convert);
	if (hs_periods_bad != 0 || hs_periods_short != 0) fail("safe raster line period");
	if (lines_per_frame_last != 262) fail("safe raster lines per frame");
	phase_done("4 safe raster");

	// ---- 5. offsets: +1 us left edge, +8 lines down (mode 13h, 524 rows)
	set_mode13h; vtotal = 524; expected_period = 2 * 2701; hpos = 1; vpos = 1;
	wait_frames(5); @(posedge vs); @(posedge clk); @(posedge clk); clear_stats;
	wait_frames(2); @(posedge clk); @(posedge clk);
	$display("offsets: top %0d (expected ~50), de offset %0d clk (expected ~935), pixel errors %0d", pic_top_last, de_ofs_last, pix_errors);
	if (pic_top_last < 48 || pic_top_last > 53) fail("V offset");
	if (de_ofs_last < 935 - 8 || de_ofs_last > 935 + 40) fail("H offset");
	if (pix_errors != 0) fail("offset pixels");
	phase_done("5 offsets");

	if (total_errors == 0) $display("PASS"); else $display("FAILED with %0d errors", total_errors);
	$finish;
end

endmodule
