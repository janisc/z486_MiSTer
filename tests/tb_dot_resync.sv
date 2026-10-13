// Unit test of dot_resync fed by dotclk_ce: the renderer (85 MHz) pushes one entry per dot enable, a
// counting pixel value with a marker on the first dot of each pixel (every dot, or one in three in the
// 24bpp phase), and the dot-clock side must read the same sequence without gaps or repeats, with rce on
// exactly the marked dots, at a bounded fill level; a rate switch mid-stream must stay centred. Two
// fallback cases: the dot clock stands still while the renderer pushes from its own divider (a PLL
// between families), and the renderer's divider runs faster than the dot clock for a while; both must
// end in a re-centred FIFO that runs on without errors (hold = the renderer not slaved).
// Run: iverilog -g2012 -o /tmp/tb_dot_resync tests/tb_dot_resync.sv src/soc/dot_resync.v src/soc/dotclk_ce.v && vvp /tmp/tb_dot_resync
`timescale 1ps/1ps
module tb_dot_resync;

reg clk = 0;                 // 85 MHz renderer clock
reg dotclk = 0;
integer dot_half = 19860;    // 25.175861 MHz
reg dot_run = 1;             // 0: the dot clock stands still
reg valid = 0;
wire ce;
reg mode24 = 0;              // 1: a pixel is three dots
reg [26:0] wdata = 0;        // the pixel value
reg wpix = 1;
wire rce, running;
wire [26:0] rdata;
wire [7:0] resyncs;
integer expect_next, errors = 0, got = 0, pixels = 0, i, t;
reg [1:0] phase = 0;
reg free = 0;                // 1: the renderer pushes from its own fractional divider (the fallback)
integer free_rate = 25175861;
reg [27:0] frac_acc = 0;
reg frac_ce = 0;
reg check = 1;               // 0: a disturbance is under way, sequence errors are expected
wire wce = free ? frac_ce : ce;

always #5882 clk = ~clk;
always #(dot_half) if (dot_run) dotclk = ~dotclk;

dotclk_ce ce_gen(.clk(clk), .dotclk(dotclk), .valid(valid), .ce(ce));
dot_resync dut(.wclk(clk), .wce(wce), .wpix(wpix), .wdata(wdata), .rclk(dotclk), .hold(free | ~valid),
               .rce(rce), .rdata(rdata), .running(running), .resyncs(resyncs));

// the renderer's own divider: free_rate enables a second from the 85 MHz clock
always @(posedge clk) begin
	frac_ce <= 0;
	if (frac_acc + free_rate >= 28'd85000000) begin frac_acc <= frac_acc + free_rate - 28'd85000000; frac_ce <= 1; end
	else frac_acc <= frac_acc + free_rate;
end

// renderer: after each pushed dot, the next dot's value and marker (a new pixel every dot, or every third)
always @(posedge clk) begin
	if (wce) begin
		if (!mode24 || phase == 2) begin wdata <= wdata + 1; wpix <= 1; phase <= 0; end
		else begin wpix <= 0; phase <= phase + 1; end
	end
end

// checker: a marked dot carries the next value, an unmarked one repeats the last
reg first = 1;
always @(posedge dotclk) begin
	if (dut.pop_q) begin
		got = got + 1;
		if (first) begin expect_next = rdata + 1; first = 0; if (rce) pixels = pixels + 1; end
		else if (rce) begin
			pixels = pixels + 1;
			if (check && rdata !== expect_next) begin
				errors = errors + 1;
				if (errors < 5) $display("  gap at output %0d: got %0d expected %0d", got, rdata, expect_next);
			end
			expect_next = rdata + 1;
		end
		else if (check && rdata !== expect_next - 1) begin
			errors = errors + 1;
			if (errors < 5) $display("  repeat dot at output %0d: got %0d expected %0d", got, rdata, expect_next - 1);
		end
	end
end

integer occ_min = 999, occ_max = 0, p0, g0;
task settle_and_check(input integer cycles, input string label);
	begin
		occ_min = 999; occ_max = 0; p0 = pixels; g0 = got;
		for (t = 0; t < cycles; t = t + 1) begin
			@(posedge dotclk);
			if (running) begin
				if (dut.occ < occ_min) occ_min = dut.occ;
				if (dut.occ > occ_max) occ_max = dut.occ;
			end
		end
		$display("%s: running=%0d fill %0d..%0d resyncs=%0d errors=%0d dots %0d pixels %0d  %s", label, running, occ_min, occ_max,
		         resyncs, errors, got - g0, pixels - p0,
		         (running && errors == 0 && occ_min >= 8 && occ_max <= 24 &&
		          (mode24 ? (got - g0 >= 3 * (pixels - p0) - 48 && got - g0 <= 3 * (pixels - p0) + 48) : (got - g0 == pixels - p0))) ? "ok" : "FAIL");   // 24bpp: the window starts with a few entries of the previous mode
	end
endtask

initial begin
	#200000 valid = 1;
	settle_and_check(20000, "25.175 MHz steady");
	// clock family change: 25.175 -> 28.322 (renderer follows at once through dotclk_ce, the FIFO must stay centred)
	dot_half = 17654; first = 1;
	settle_and_check(20000, "28.322 MHz after switch");
	// rate mismatch: the renderer keeps pushing while the dot clock stops for a while (PLL relock), then returns
	valid = 0; #(2000000); valid = 1; first = 1;
	settle_and_check(20000, "after a 2 us enable gap");
	// 24bpp: 75 MHz dots, a pixel every three
	valid = 0; dot_half = 6665; mode24 = 1; #100000 valid = 1; first = 1;
	settle_and_check(60000, "75 MHz dots, pixel per 3");
	// the PLL reprograms: the dot clock stands still for 3 us while the renderer pushes from its own divider
	valid = 0; mode24 = 0; dot_half = 19860; free = 1; check = 0; dot_run = 0;
	#3000000 dot_run = 1;
	#500000 free = 0; valid = 1;
	#500000 first = 1; check = 1;
	settle_and_check(20000, "after a 3 us dot-clock stop");
	// the renderer's divider 12 % faster than the dot clock for 20 us (a fallback at the wrong rate), then slaved again
	free_rate = 28322000; free = 1; check = 0;
	#20000000 free = 0;
	#500000 first = 1; check = 1;
	settle_and_check(20000, "after 20 us of a faster renderer");
	if (errors == 0 && resyncs == 0) $display("ALL OK (%0d dots through, no spontaneous re-centring)", got);
	else $display("FAILED: %0d errors, %0d re-centrings", errors, resyncs);
	$finish;
end

endmodule
