// dot_pll_cfg: the dot-clock PLL's reconfiguration (rtl/pll_video.v).
//
// The framework's altera_pll_reconfig IP (sys/pll_cfg, untouched: a copy trimmed to
// one output counter did not reconfigure the PLL on the card either, build 9 of
// 2026-10-13) does the DPRIO work, driven over its Avalon slave by the table machine below:
// per request the six writes of the original table machine (waitrequest mode, N
// bypassed, M = 18, K, C0 for counter 0 without bypass or odd division, start),
// each when the core is not holding waitrequest, which it does until the DPRIO
// sequence is through and the PLL has relocked. The test ports rb_c0a / rb_c0b (the
// C0 register read back at DPRIO 00h and 11h) are kept at zero: see the note in the
// table machine.
//
// Three rewrites of the DPRIO sequence in own logic (builds 4 to 7 of 2026-10-13)
// matched the core's bus cycle for cycle in simulation, landed in the PLL's
// registers (the read-back showed every value) and still left the PLL at its
// power-up output; the core changes it. Whatever the difference is, it is below
// what the simulation models and the post-fit netlists show, so the core stays.
module dot_pll_cfg
(
	input             clk,              // the PLL's management clock (50 MHz); it is also the DPRIO clock
	input             req,              // level: reconfigure to the values below (edge-detected)
	input       [7:0] c0_hi,            // C0 high and low counts (even divider: both div/2)
	input       [7:0] c0_lo,
	input      [31:0] m_frac,           // K: the fractional part of M, 32 bits
	output reg        busy,             // 1 from the request to the end of the sequence and the read-back
	output            ready,            // 1 when the core takes requests (initialized, the PLL locked, idle)
	output            locked,           // the PLL's lock, synchronized
	output reg [15:0] rb_c0a,           // the C0 register read back at 00h after the last request
	output reg [15:0] rb_c0b,           // the same at 11h (the other half of a DPRIO pair's map)
	output     [63:0] reconfig_to_pll,
	input      [63:0] reconfig_from_pll
);

wire        mgmt_waitrequest;
wire [31:0] mgmt_readdata;
reg         mgmt_write = 1'b0;
reg         mgmt_read  = 1'b0;
reg   [5:0] mgmt_address = 6'd0;
reg  [31:0] mgmt_writedata = 32'd0;

pll_cfg core                           // the framework's reconfiguration IP, untouched (sys/pll_cfg)
(
	.mgmt_clk          (clk),
	.mgmt_reset        (1'b0),
	.mgmt_waitrequest  (mgmt_waitrequest),
	.mgmt_read         (mgmt_read),
	.mgmt_readdata     (mgmt_readdata),
	.mgmt_write        (mgmt_write),
	.mgmt_address      (mgmt_address),
	.mgmt_writedata    (mgmt_writedata),
	.reconfig_to_pll   (reconfig_to_pll),
	.reconfig_from_pll (reconfig_from_pll)
);

assign ready = ~mgmt_waitrequest;

reg [1:0] lock_s = 2'b00;
always @(posedge clk) lock_s <= {lock_s[0], reconfig_from_pll[16]};
assign locked = lock_s[1];

// ---- the table machine: one Avalon transaction every other step while the core is not waiting
localparam MODE_REG = 6'd0, STATUS_REG = 6'd1, START_REG = 6'd2, N_REG = 6'd3, M_REG = 6'd4, C_REG = 6'd5,
           DSM_REG = 6'd7, ANY_DPRIO = 6'h20;
reg  [4:0] step = 5'd0;                 // 0: idle
reg        req_d = 1'b0;
reg  [7:0] c0_hi_r, c0_lo_r;
reg [31:0] k_r;

initial begin
	busy   = 1'b0;
	rb_c0a = 16'd0;
	rb_c0b = 16'd0;
end

reg        pending = 1'b0;              // a request taken, the sequence not started yet (the core may be waiting)

always @(posedge clk) begin
	req_d      <= req;
	mgmt_write <= 1'b0;
	mgmt_read  <= 1'b0;
	if (step == 5'd0) begin
		if (pending && !mgmt_waitrequest) begin
			pending <= 1'b0;
			step    <= 5'd1;
		end
		else if (!pending) busy <= 1'b0;
	end
	else if (!mgmt_waitrequest) begin
		step <= (step == 5'd12) ? 5'd0 : step + 1'd1;
		case (step)
			5'd1:  begin mgmt_address <= MODE_REG;  mgmt_writedata <= 32'd0;                                   mgmt_write <= 1'b1; end   // waitrequest mode
			5'd3:  begin mgmt_address <= N_REG;     mgmt_writedata <= 32'h0001_0000;                           mgmt_write <= 1'b1; end   // N bypassed (/1)
			5'd5:  begin mgmt_address <= M_REG;     mgmt_writedata <= 32'h0000_0909;                           mgmt_write <= 1'b1; end   // M = 18 (9 + 9)
			5'd7:  begin mgmt_address <= DSM_REG;   mgmt_writedata <= k_r;                                     mgmt_write <= 1'b1; end   // K
			5'd9:  begin mgmt_address <= C_REG;     mgmt_writedata <= {14'd0, 2'b00, c0_hi_r, c0_lo_r};        mgmt_write <= 1'b1; end   // C0: counter 0, no bypass, no odd division
			5'd11: begin mgmt_address <= START_REG; mgmt_writedata <= 32'd0;                                   mgmt_write <= 1'b1; end   // start: the core holds waitrequest until done and locked
			// No read-back here: builds 6 to 8 read the DPRIO registers back a few clocks after the last write,
			// while the block was still shifting the new configuration into the PLL, and the PLL never took it;
			// the core's own read path is only blocked while its state machine waits for lock, and it leaves
			// that state at once if the PLL has not dropped lock yet. The test ports stay, at zero.
			default: ;
		endcase
	end
	if (req && !req_d) begin             // last, so that busy rises even when the idle branch cleared it this clock
		c0_hi_r <= c0_hi; c0_lo_r <= c0_lo; k_r <= m_frac;
		pending <= 1'b1;
		busy    <= 1'b1;
	end
end

endmodule
