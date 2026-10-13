// Unit test of dotclk_ce: the enable count equals the dot-clock edge count for the
// fork's dot rates against the 85 MHz renderer clock, and the catch-up never exceeds
// a few steps. Run: iverilog -g2012 -o /tmp/tb_dotclk_ce tests/tb_dotclk_ce.sv src/soc/dotclk_ce.v && vvp /tmp/tb_dotclk_ce
`timescale 1ps/1ps
module tb_dotclk_ce;

reg clk = 0;
reg dotclk = 0;
reg valid = 0;
wire ce;
integer dot_half;           // half period of the dot clock in ps
integer edges, enables, lag, maxlag, i, t;
integer fails = 0;

dotclk_ce dut(.clk(clk), .dotclk(dotclk), .valid(valid), .ce(ce));

always #5882 clk = ~clk;    // 85 MHz (11.765 ns)

task run_rate(input integer hz, input integer dots);
	begin
		dot_half = 1_000_000_000_000 / hz / 2;
		edges = 0; enables = 0; maxlag = 0;
		valid = 0;
		repeat (20) @(posedge clk);
		valid = 1;
		fork
			begin : gen
				for (i = 0; i < dots; i = i + 1) begin
					#(dot_half) dotclk = 1; edges = edges + 1;
					#(dot_half) dotclk = 0;
				end
			end
			begin : cnt
				for (t = 0; t < dots * 4; t = t + 1) begin
					@(posedge clk);
					if (ce) enables = enables + 1;
					lag = edges - enables;
					if (lag > maxlag) maxlag = lag;
					if (i == dots && edges == enables) t = dots * 4;  // done
				end
			end
		join
		repeat (10) @(posedge clk) if (ce) enables = enables + 1;
		$display("%9d Hz: %0d edges, %0d enables, max lag %0d %s", hz, edges, enables, maxlag,
		         (edges == enables && maxlag <= 6) ? "ok" : "FAIL");
		if (edges != enables || maxlag > 6) fails = fails + 1;
	end
endtask

initial begin
	run_rate(25_175_861, 4000);
	run_rate(28_322_843, 4000);
	run_rate(35_892_783, 4000);
	run_rate(64_985_607, 4000);
	run_rate(75_024_065, 4000);
	// valid dropping and rising: no backlog
	valid = 0;
	for (i = 0; i < 100; i = i + 1) begin #(20000) dotclk = ~dotclk; end
	enables = 0; valid = 1;
	repeat (30) @(posedge clk) if (ce) enables = enables + 1;
	// edges still in the synchronizer when valid rises (up to three) come out as enables: harmless
	$display("after valid=0..1 with 50 edges unseen: %0d enables %s", enables, enables <= 3 ? "ok" : "FAIL");
	if (enables > 3) fails = fails + 1;
	if (fails) $display("FAILED: %0d", fails); else $display("ALL OK");
	$finish;
end

endmodule
