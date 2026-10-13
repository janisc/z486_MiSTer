// dot_pll_cfg: a minimal reconfiguration driver for the dot-clock PLL (rtl/pll_video.v).
//
// The framework's altera_pll_reconfig IP does this job in 1,509 ALMs, with shadow
// registers for 18 counters, phase shifting, a MIF ROM and an Avalon slave. This core
// only ever changes the output counter C0 and the fractional part K of M (M's integer
// part, N and the counters' bypass and odd-division bits keep their power-up values),
// so this driver speaks the PLL's DPRIO interface (reconfig_to_pll / reconfig_from_pll)
// for exactly that, the way the IP does it:
//
//  * power-up: the DPRIO reset held for 341 clocks, then 64 writes of zero to the
//    addresses 0..63 and the mdio_dis / ser_shift_load hand-over pattern of the IP's
//    fpll_dprio_init, after which mdio_dis stays 0 and ser_shift_load 1;
//  * a request: write C0 (address 00h, {high, low}); read register 17h (it holds the
//    odd-division enables of C0..C3, the VCO post-divider bit and the K-ready bit 11),
//    write it back with bit 11 clear, write K's low and high halves (18h, 19h), write
//    17h back with bit 11 set. The PLL relocks by itself; the IP's state machine issues
//    the same writes in the same order (its states ONE and EIGHT to TEN).
//
// DPRIO transactions are one clock wide; a read's data is on reconfig_from_pll[15:0]
// two clocks after the read, captured here three clocks after, as the IP does.
module dot_pll_cfg
(
	input             clk,              // the PLL's management clock (50 MHz); it is also the DPRIO clock
	input             req,              // level: reconfigure to the values below (edge-detected)
	input       [7:0] c0_hi,            // C0 high and low counts (even divider: both div/2)
	input       [7:0] c0_lo,
	input      [31:0] m_frac,           // K: the fractional part of M, 32 bits
	output reg        busy,             // 1 from the request to the last write
	output reg        ready,            // 1 once the power-up initialization is over
	output            locked,           // the PLL's lock, synchronized
	output     [63:0] reconfig_to_pll,
	input      [63:0] reconfig_from_pll
);

// ---- power-up: DPRIO reset, then the init writes (altera_pll_reconfig_core's self_reset and fpll_dprio_init)
reg  [8:0] rst_cnt = 9'd0;
reg        init_reset = 1'b1;           // reconfig_to_pll[1] = ~init_reset
reg  [1:0] rst_sync = 2'b00;            // the IP's two-flop release of its init counter: two extra writes at 0
reg  [6:0] icnt = 7'd0;                 // 0..63 writes, 64..71 the hand-over pattern, holds at 71
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
			if (icnt == 7'd71) init_done <= 1'b1;
			else icnt <= icnt + 1'd1;
		end
	end
	// the IP's levels: during the init writes mdio_dis = 1 and ser_shift_load = 1; from count 64 on
	// ser_shift_load = |count[2:1] and mdio_dis = ~count[2], which end at 1 and 0 with the count held at 71
	mdio_dis       <= init_reset ? 1'b1 : (icnt[6] ? ~icnt[2] : 1'b1);
	ser_shift_load <= init_reset ? 1'b1 : (icnt[6] ? |icnt[2:1] : 1'b1);
	ready          <= init_done;
end

wire        init_write = !init_reset && !init_done && !icnt[6];
wire  [5:0] init_addr  = icnt[5:0];

// ---- the request sequence: what the framework IP writes for the table machine's six Avalon
// writes (N bypassed, M = 18, K, C0, start), register by register:
//   13h N = {0, 0}; 12h M = {9, 9}; 00h C0 = {hi, lo};
//   15h (bypass enables) read, written back with N's bit 5 set and M's bit 4, C0's bit 3 clear;
//   17h (odd-division enables, VCO bit, K-ready bit 11) read, written back with bits 5, 4, 3 clear
//       and bit 11 clear; 18h, 19h = K; 17h again with bit 11 set.
localparam S_IDLE = 4'd0, S_N = 4'd1, S_M = 4'd2, S_C0 = 4'd3, S_RD15 = 4'd4, S_RD17 = 4'd5, S_W1 = 4'd6,
           S_CAP15 = 4'd7, S_CAP17 = 4'd8, S_W15 = 4'd9, S_KCLR = 4'd10, S_KLO = 4'd11, S_KHI = 4'd12,
           S_KSET = 4'd13;
reg  [3:0] st = S_IDLE;
reg        req_d = 1'b0;
reg [15:0] r15 = 16'd0, r17 = 16'd0;
reg  [7:0] c0_hi_r, c0_lo_r;
reg [31:0] k_r;

reg        dp_write = 1'b0, dp_read = 1'b0;
reg  [5:0] dp_addr = 6'd0;
reg [15:0] dp_data = 16'd0;

always @(posedge clk) begin
	req_d <= req;
	dp_write <= 1'b0;
	dp_read  <= 1'b0;
	case (st)
		S_IDLE: begin
			busy <= 1'b0;
			if (init_done && req && !req_d) begin
				c0_hi_r <= c0_hi; c0_lo_r <= c0_lo; k_r <= m_frac;
				busy <= 1'b1;
				st <= S_N;
			end
		end
		S_N:     begin dp_write <= 1'b1; dp_addr <= 6'h13; dp_data <= 16'h0000;           st <= S_M;     end
		S_M:     begin dp_write <= 1'b1; dp_addr <= 6'h12; dp_data <= 16'h0909;           st <= S_C0;    end
		S_C0:    begin dp_write <= 1'b1; dp_addr <= 6'h00; dp_data <= {c0_hi_r, c0_lo_r}; st <= S_RD15;  end
		S_RD15:  begin dp_read  <= 1'b1; dp_addr <= 6'h15;                                st <= S_RD17;  end
		S_RD17:  begin dp_read  <= 1'b1; dp_addr <= 6'h17;                                st <= S_W1;    end
		S_W1:    st <= S_CAP15;                                                                           // read data arrives two clocks after the read
		S_CAP15: begin r15 <= reconfig_from_pll[15:0];                                    st <= S_CAP17; end
		S_CAP17: begin r17 <= reconfig_from_pll[15:0];                                    st <= S_W15;   end
		S_W15:   begin dp_write <= 1'b1; dp_addr <= 6'h15; dp_data <= (r15 & ~16'h0038) | 16'h0020; st <= S_KCLR; end
		S_KCLR:  begin dp_write <= 1'b1; dp_addr <= 6'h17; dp_data <= r17 & ~16'h0838;    st <= S_KLO;   end
		S_KLO:   begin dp_write <= 1'b1; dp_addr <= 6'h18; dp_data <= k_r[15:0];          st <= S_KHI;   end
		S_KHI:   begin dp_write <= 1'b1; dp_addr <= 6'h19; dp_data <= k_r[31:16];         st <= S_KSET;  end
		S_KSET:  begin dp_write <= 1'b1; dp_addr <= 6'h17; dp_data <= (r17 & ~16'h0038) | 16'h0800; st <= S_IDLE; end
		default: st <= S_IDLE;
	endcase
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
assign reconfig_to_pll[27:26] = 2'b11;                                 // byte enables, always both
assign reconfig_to_pll[28]    = ser_shift_load;
assign reconfig_to_pll[29]    = mdio_dis;
assign reconfig_to_pll[30]    = 1'b0;                                  // phase_en
assign reconfig_to_pll[31]    = 1'b0;                                  // up_dn
assign reconfig_to_pll[36:32] = 5'd0;                                  // cnt_sel
assign reconfig_to_pll[37]    = 1'b0;                                  // scanen
assign reconfig_to_pll[38]    = 1'b0;                                  // atpgmode
assign reconfig_to_pll[63:39] = 25'd0;

endmodule
