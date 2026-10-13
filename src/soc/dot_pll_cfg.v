// dot_pll_cfg: a minimal reconfiguration driver for the dot-clock PLL (rtl/pll_video.v).
//
// The framework's altera_pll_reconfig IP does this job in 1,221 ALMs, with shadow
// registers for 18 counters, phase shifting, a MIF ROM and an Avalon slave. This core
// only ever changes the output counter C0 and the fractional part K of M (M's integer
// part, N and the counters' bypass and odd-division bits keep their power-up values),
// so this driver speaks the PLL's DPRIO interface (reconfig_to_pll / reconfig_from_pll)
// for exactly that, and it does so with the IP's bus, cycle for cycle:
//
//  * power-up: the DPRIO reset held for 341 clocks, then 64 writes of zero to the
//    addresses 0..63 (two more at address 0 first, from the IP's reset synchronizer)
//    and the mdio_dis / ser_shift_load hand-over pattern of the IP's fpll_dprio_init
//    with the address held at 0, after which mdio_dis stays 0 and ser_shift_load 1;
//  * a request, as the IP's states ONE..TEN do it for the six Avalon writes of the
//    original table machine: for each of N, M and C0 the counter value (13h, 12h,
//    00h), reads of the bypass register 15h and the odd-division register 17h, two
//    idle cycles while the data arrive, then both registers written back with that
//    counter's bit changed (N bypassed, M and C0 not, no odd division); then K: 17h
//    read, written back with the K-ready bit 11 clear, K's low and high halves
//    (18h, 19h), 17h with the ready bit set. The PLL relocks by itself. Idle cycles
//    drive address, data and byte enables to zero, as the IP does. Finally the C0
//    register is read back at 00h and at 11h (rb_c0a, rb_c0b) for the test tools.
//
// DPRIO transactions are one clock wide; a read's data is on reconfig_from_pll[15:0]
// two clocks after the strobe. The outputs here are registered, so the bus runs one
// clock behind the step counter; the captures are placed accordingly.
//
// The first version wrote the same registers in a different order, let the address
// keep counting through the hand-over pattern and held the byte enables at 11
// between transactions; the register contents matched the IP's in simulation, but
// on the card the PLL never left its power-up configuration (builds 4 and 5 of
// 2026-10-13). Hence the exact copy.
//
// FPLL1: the fractional PLLs come in pairs on one DPRIO block and the second PLL of a
// pair mirrors the counter registers (its C0 is at 11h; the IP has the fitter patch a
// LUT for this). The fitter reports the first half for every location this core has
// used (X0_Y1, X0_Y15, X89_Y1), so the default map is 0.
module dot_pll_cfg #(parameter FPLL1 = 0)
(
	input             clk,              // the PLL's management clock (50 MHz); it is also the DPRIO clock
	input             req,              // level: reconfigure to the values below (edge-detected)
	input       [7:0] c0_hi,            // C0 high and low counts (even divider: both div/2)
	input       [7:0] c0_lo,
	input      [31:0] m_frac,           // K: the fractional part of M, 32 bits
	output reg        busy,             // 1 from the request to the end of the sequence
	output reg        ready,            // 1 once the power-up initialization is over
	output            locked,           // the PLL's lock, synchronized
	output reg [15:0] rb_c0a,           // the C0 register read back at 00h after the last request
	output reg [15:0] rb_c0b,           // the same at 11h (the other half's map)
	output     [63:0] reconfig_to_pll,
	input      [63:0] reconfig_from_pll
);

localparam [5:0] C0_ADDR = FPLL1 ? 6'h11 : 6'h00;

// ---- power-up: DPRIO reset, then the init writes (altera_pll_reconfig_core's self_reset and fpll_dprio_init)
reg  [8:0] rst_cnt = 9'd0;
reg        init_reset = 1'b1;           // reconfig_to_pll[1] = ~init_reset
reg  [1:0] rst_sync = 2'b00;            // the IP's two-flop release of its init counter: two extra writes at 0
reg  [6:0] icnt = 7'd0;                 // 0..63 writes, 64..68 the hand-over pattern, holds at 68
reg        init_done = 1'b0;
reg        mdio_dis = 1'b1;
reg        ser_shift_load = 1'b1;

always @(posedge clk) begin
	if (init_reset) begin
		if (rst_cnt == 9'd341) init_reset <= 1'b0;
		else rst_cnt <= rst_cnt + 1'd1;
	end
	else begin
		rst_sync <= {rst_sync[0], 1'b1};
		if (rst_sync[1] && !init_done) begin
			if (icnt == 7'd68) init_done <= 1'b1;     // the IP's done flag rises with mdio_dis's fall; the pattern is level from here
			else icnt <= icnt + 1'd1;
		end
	end
	// the IP's levels: during the init writes mdio_dis = 1 and ser_shift_load = 1; from count 64 on
	// ser_shift_load = |count[2:1] and mdio_dis = ~count[2], which end at 1 and 0 with the count held at 68
	mdio_dis       <= init_reset ? 1'b1 : (icnt[6] ? ~icnt[2] : 1'b1);
	ser_shift_load <= init_reset ? 1'b1 : (icnt[6] ? |icnt[2:1] : 1'b1);
	ready          <= init_done;
end

wire        init_write = !init_reset && !init_done && !icnt[6];
wire  [5:0] init_addr  = icnt[6] ? 6'd0 : icnt[5:0];      // address 0 through the hand-over, as the IP

// ---- the request sequence, one step a clock (see the header)
localparam [5:0] LAST = 6'd36;
reg  [5:0] step = 6'd0;                 // 0: idle
reg        req_d = 1'b0;
reg [15:0] r15 = 16'd0, r17 = 16'd0;
reg  [7:0] c0_hi_r, c0_lo_r;
reg [31:0] k_r;

reg        dp_write = 1'b0, dp_read = 1'b0;
reg  [5:0] dp_addr = 6'd0;
reg [15:0] dp_data = 16'd0;
reg  [1:0] dp_be = 2'b00;

initial begin
	busy   = 1'b0;
	rb_c0a = 16'd0;
	rb_c0b = 16'd0;
end

task automatic wr(input [5:0] a, input [15:0] d);
	begin dp_write <= 1'b1; dp_be <= 2'b11; dp_addr <= a; dp_data <= d; end
endtask
task automatic rd(input [5:0] a);
	begin dp_read <= 1'b1; dp_be <= 2'b11; dp_addr <= a; end
endtask

always @(posedge clk) begin
	req_d    <= req;
	dp_write <= 1'b0;                   // idle: zeros on the bus, as the IP
	dp_read  <= 1'b0;
	dp_addr  <= 6'd0;
	dp_data  <= 16'd0;
	dp_be    <= 2'b00;
	if (step == 6'd0) begin
		busy <= 1'b0;
		if (init_done && req && !req_d) begin
			c0_hi_r <= c0_hi; c0_lo_r <= c0_lo; k_r <= m_frac;
			busy <= 1'b1;
			step <= 6'd1;
		end
	end
	else begin
		step <= (step == LAST) ? 6'd0 : step + 1'd1;
		case (step)
			// N: value, reads, captures (two clocks after the strobe, which is one behind the step), write-backs
			6'd1:  wr(6'h13, 16'h0000);
			6'd2:  rd(6'h15);
			6'd3:  rd(6'h17);
			6'd5:  r15 <= reconfig_from_pll[15:0];
			6'd6:  begin r17 <= reconfig_from_pll[15:0]; wr(6'h15, r15 | 16'h0020); end      // N bypassed
			6'd7:  wr(6'h17, r17 & ~16'h0020);                                                 // no odd division
			// M
			6'd8:  wr(6'h12, 16'h0909);
			6'd9:  rd(6'h15);
			6'd10: rd(6'h17);
			6'd12: r15 <= reconfig_from_pll[15:0];
			6'd13: begin r17 <= reconfig_from_pll[15:0]; wr(6'h15, r15 & ~16'h0010); end     // M not bypassed
			6'd14: wr(6'h17, r17 & ~16'h0010);
			// C0
			6'd15: wr(C0_ADDR, {c0_hi_r, c0_lo_r});
			6'd16: rd(6'h15);
			6'd17: rd(6'h17);
			6'd19: r15 <= reconfig_from_pll[15:0];
			6'd20: begin r17 <= reconfig_from_pll[15:0]; wr(6'h15, r15 & ~16'h0008); end     // C0 not bypassed
			6'd21: wr(6'h17, r17 & ~16'h0008);
			// K: the ready bit clear, the value, the ready bit set
			6'd22: rd(6'h17);
			6'd25: begin r17 <= reconfig_from_pll[15:0]; dp_be <= 2'b11; dp_data <= reconfig_from_pll[15:0]; end   // the IP's SIX: enables and data up, no strobe
			6'd26: wr(6'h17, r17 & ~16'h0800);
			6'd27: wr(6'h18, k_r[15:0]);
			6'd28: wr(6'h19, k_r[31:16]);
			6'd29: wr(6'h17, r17 | 16'h0800);
			// read back C0 under both maps for the test tools
			6'd31: rd(6'h00);
			6'd32: rd(6'h11);
			6'd34: rb_c0a <= reconfig_from_pll[15:0];
			6'd35: rb_c0b <= reconfig_from_pll[15:0];
			default: ;
		endcase
	end
end

// ---- lock, synchronized as the IP does
reg [1:0] lock_s = 2'b00;
always @(posedge clk) lock_s <= {lock_s[0], reconfig_from_pll[16]};
assign locked = lock_s[1];

// ---- the bus (the IP's bit map)
assign reconfig_to_pll[0]     = clk;                                   // dprio_clk
assign reconfig_to_pll[1]     = ~init_reset;
assign reconfig_to_pll[2]     = init_done ? dp_write : init_write;
assign reconfig_to_pll[3]     = init_done ? dp_read  : 1'b0;
assign reconfig_to_pll[9:4]   = init_done ? dp_addr  : init_addr;
assign reconfig_to_pll[25:10] = init_done ? dp_data  : 16'd0;
assign reconfig_to_pll[27:26] = init_done ? dp_be    : 2'b11;          // byte enables: both during the init, else per transaction
assign reconfig_to_pll[28]    = ser_shift_load;
assign reconfig_to_pll[29]    = mdio_dis;
assign reconfig_to_pll[30]    = 1'b0;                                  // phase_en
assign reconfig_to_pll[31]    = 1'b0;                                  // up_dn
assign reconfig_to_pll[36:32] = 5'd0;                                  // cnt_sel
assign reconfig_to_pll[37]    = 1'b0;                                  // scanen
assign reconfig_to_pll[38]    = 1'b0;                                  // atpgmode
assign reconfig_to_pll[63:39] = 25'd0;

endmodule
