// Co-simulation of dot_pll_cfg against the framework's altera_pll_reconfig IP (sys/pll_cfg/pll_cfg.v):
// both drive a small model of the PLL's DPRIO register file; the IP gets the Avalon writes of the
// z486_mister.sv table machine (mode, N bypass, M, K, C0, start), the driver gets a request with the
// same values. After each family the two models must hold identical registers, and the K-ready bit
// must have been cleared before and set after the K writes. Also checks the power-up init writes.
// Run (WSL): iverilog -g2012 -o /tmp/tb_dot_pll_cfg tests/tb_dot_pll_cfg.sv src/soc/dot_pll_cfg.v \
//   sys/pll_cfg/pll_cfg.v sys/pll_cfg/altera_pll_reconfig_top.v sys/pll_cfg/altera_pll_reconfig_core.v && vvp /tmp/tb_dot_pll_cfg
`timescale 1ns/1ps

// simulation stands-ins for the two Altera primitives the IP uses
module altera_std_synchronizer #(parameter depth = 3) (input clk, input reset_n, input din, output dout);
	reg [depth-1:0] s = 0;
	always @(posedge clk or negedge reset_n) if (!reset_n) s <= 0; else s <= {s[depth-2:0], din};
	assign dout = s[depth-1];
endmodule
module cyclonev_lcell_comb #(parameter lut_mask = 64'h0, parameter dont_touch = "off")
(input dataa, datab, datac, datad, datae, dataf, output combout);
	assign combout = lut_mask[{dataf, datae, datad, datac, datab, dataa}];
endmodule

// DPRIO register file: 64 x 16, writes with both byte enables, reads answered two clocks later; locked = 1.
// Counts the init writes and watches the K-ready handshake.
module dprio_model
(
	input         clk,
	input  [63:0] to_pll,
	output [63:0] from_pll,
	output reg [15:0] regs [0:63],
	output integer init_writes,
	output integer kready_clears, kready_sets, k_writes_between
);
	wire        wr = to_pll[2], rd = to_pll[3];
	wire  [5:0] addr = to_pll[9:4];
	wire [15:0] wdata = to_pll[25:10];
	reg  [15:0] rd1 = 0, rd2 = 0;
	reg         kready_low = 0;
	integer i;
	initial begin
		for (i = 0; i < 64; i = i + 1) regs[i] = 0;
		regs[6'h00] = 16'h1010;     // C0 = 32 (power-up)
		regs[6'h12] = 16'h0909;     // M = 18
		regs[6'h13] = 16'h0000;     // N (bypassed)
		regs[6'h15] = 16'h0020;     // N bypass enable (bit 5)
		regs[6'h17] = 16'h0900;     // VCO post-divider bit 8 set, K ready bit 11 set
		regs[6'h18] = 16'hC3BD;     // K = 543827773 = 0x206AC3BD
		regs[6'h19] = 16'h206A;
		init_writes = 0; kready_clears = 0; kready_sets = 0; k_writes_between = 0;
	end
	always @(posedge clk) begin
		rd1 <= regs[addr];
		rd2 <= rd1;
		if (wr) begin
			init_writes = init_writes + 1;                     // every write; 64 expected before the first request
			if (addr == 6'h17) begin
				if (!wdata[11] && regs[6'h17][11]) begin kready_clears = kready_clears + 1; kready_low = 1; end
				if (wdata[11] && !regs[6'h17][11]) begin kready_sets = kready_sets + 1; kready_low = 0; end
			end
			if ((addr == 6'h18 || addr == 6'h19) && kready_low) k_writes_between = k_writes_between + 1;
			regs[addr] <= wdata;
		end
	end
	assign from_pll[15:0] = rd2;
	assign from_pll[16] = 1'b1;
	assign from_pll[63:17] = 0;
endmodule

module tb_dot_pll_cfg;
reg clk = 0;
always #10 clk = ~clk;      // 50 MHz

// --- the IP, driven like z486_mister.sv's table machine
wire [63:0] ip_to, ip_from;
wire        ip_wait;
reg         ip_write = 0;
reg   [5:0] ip_addr = 0;
reg  [31:0] ip_data = 0;
pll_cfg ip (.mgmt_clk(clk), .mgmt_reset(1'b0), .mgmt_waitrequest(ip_wait), .mgmt_read(1'b0), .mgmt_readdata(),
            .mgmt_write(ip_write), .mgmt_address(ip_addr), .mgmt_writedata(ip_data),
            .reconfig_to_pll(ip_to), .reconfig_from_pll(ip_from));
wire [15:0] ip_regs [0:63];
integer ip_init, ip_clr, ip_set, ip_kb;
dprio_model ip_model (.clk(clk), .to_pll(ip_to), .from_pll(ip_from), .regs(ip_regs),
                      .init_writes(ip_init), .kready_clears(ip_clr), .kready_sets(ip_set), .k_writes_between(ip_kb));

// --- the driver
wire [63:0] dr_to, dr_from;
reg         dr_req = 0;
reg   [7:0] dr_hi = 0, dr_lo = 0;
reg  [31:0] dr_k = 0;
wire        dr_busy, dr_ready, dr_locked;
dot_pll_cfg dr (.clk(clk), .req(dr_req), .c0_hi(dr_hi), .c0_lo(dr_lo), .m_frac(dr_k), .busy(dr_busy), .ready(dr_ready),
                .locked(dr_locked), .reconfig_to_pll(dr_to), .reconfig_from_pll(dr_from));
wire [15:0] dr_regs [0:63];
integer dr_init, dr_clr, dr_set, dr_kb;
dprio_model dr_model (.clk(clk), .to_pll(dr_to), .from_pll(dr_from), .regs(dr_regs),
                      .init_writes(dr_init), .kready_clears(dr_clr), .kready_sets(dr_set), .k_writes_between(dr_kb));

task ip_wr(input [5:0] a, input [31:0] d);
	begin
		@(posedge clk); ip_addr <= a; ip_data <= d; ip_write <= 1;
		@(posedge clk); while (ip_wait) @(posedge clk);
		ip_write <= 0;
	end
endtask

integer fails = 0, i, diffs;
task compare(input string label);
	begin
		diffs = 0;
		for (i = 0; i < 64; i = i + 1) if (ip_regs[i] !== dr_regs[i]) begin
			diffs = diffs + 1;
			if (diffs < 6) $display("  reg %02h: IP %04h driver %04h", i, ip_regs[i], dr_regs[i]);
		end
		$display("%s: C0 IP %04h drv %04h, K IP %04h%04h drv %04h%04h, reg17 IP %04h drv %04h, diffs %0d, k-ready clr/set IP %0d/%0d drv %0d/%0d, K writes inside IP %0d drv %0d  %s",
		         label, ip_regs[0], dr_regs[0], ip_regs[6'h19], ip_regs[6'h18], dr_regs[6'h19], dr_regs[6'h18],
		         ip_regs[6'h17], dr_regs[6'h17], diffs, ip_clr, ip_set, dr_clr, dr_set, ip_kb, dr_kb,
		         (diffs == 0 && ip_clr == dr_clr && ip_set == dr_set && ip_kb == dr_kb) ? "ok" : "FAIL");
		if (diffs != 0 || ip_clr != dr_clr || ip_set != dr_set || ip_kb != dr_kb) fails = fails + 1;
	end
endtask

// one family, both sides: C0 = div (even), K = frac
task family(input [7:0] div, input [31:0] frac, input string label);
	begin
		fork
			begin
				ip_wr(6'd0, 32'd0);                       // waitrequest mode
				ip_wr(6'd3, 32'h0001_0000);               // N bypass
				ip_wr(6'd4, 32'h0000_0909);               // M = 18
				ip_wr(6'd7, frac);                        // K
				ip_wr(6'd5, {16'd0, 1'b0, div[7:1], 1'b0, div[7:1]});   // C0: {counter 0, hi = div/2, lo = div/2}
				ip_wr(6'd2, 32'd0);                       // start
			end
			begin
				dr_hi <= div[7:1]; dr_lo <= div[7:1]; dr_k <= frac;
				@(posedge clk); dr_req <= 1; repeat (3) @(posedge clk); dr_req <= 0;
			end
		join
		repeat (400) @(posedge clk);
		compare(label);
	end
endtask

initial begin
	// power-up initialization of both: the IP's self reset is 341 clocks, then 72 init cycles
	repeat (700) @(posedge clk);
	$display("init: driver ready=%0d; init writes IP %0d driver %0d; IP bus mdio_dis=%0d ser_shift_load=%0d driver mdio_dis=%0d ser_shift_load=%0d  %s",
	         dr_ready, ip_init, dr_init, ip_to[29], ip_to[28], dr_to[29], dr_to[28],
	         (dr_ready && ip_init == dr_init && ip_to[29] == dr_to[29] && ip_to[28] == dr_to[28]) ? "ok" : "FAIL");
	if (!(dr_ready && ip_init == dr_init && ip_to[29] == dr_to[29] && ip_to[28] == dr_to[28])) fails = fails + 1;
	compare("after the init alone");
	family(8'd36, 32'd543827773,  "family 0 (25.175)");
	family(8'd32, 32'd543827773,  "family 1 (28.322)");
	family(8'd26, 32'd2852920957, "family 3 (35.9)");
	family(8'd12, 32'd24806179,   "family 5 (24bpp)");
	family(8'd32, 32'd543827773,  "back to family 1");
	if (fails) $display("FAILED: %0d", fails); else $display("ALL OK");
	$finish;
end

endmodule
