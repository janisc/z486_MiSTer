// dot_pll_cfg: a minimal reconfiguration driver for the dot-clock PLL (rtl/pll_video.v).
//
// The framework's altera_pll_reconfig IP does this job in 1,221 ALMs, with an Avalon
// slave, shadow registers for 18 counters, a MIF reader and dynamic phase shifting.
// This core only ever changes the output counter C0 and the fractional part K of M
// (M's integer part, N and the counters' bypass and odd-division bits keep their
// power-up values), so this driver issues exactly the DPRIO transactions the IP issues
// for that, through the IP's own periphery, taken verbatim from
// sys/pll_cfg/altera_pll_reconfig_core.v:
//
//  * self_reset and fpll_dprio_init: the DPRIO reset held for 341 clocks, 64 writes
//    of zero to the addresses 0..63 and the mdio_dis / ser_shift_load hand-over
//    pattern, after which mdio_dis stays 0 and ser_shift_load 1;
//  * dprio_mux between the init block and the sequencer below, and the IP's kept
//    nets (synthesis keep) and fitter-patched cells on the way to the PLL: the
//    half flag lcell_fpll_0_1 (the fitter sets it for the second PLL of a DPRIO
//    pair, whose counter C0 sits at 11h instead of 00h), the read strobe cell and
//    the counter-select cells. Three versions with a plain copy of this periphery
//    left the PLL at its power-up configuration on the card although every bus
//    cycle matched the IP's in simulation (builds 4 to 6 of 2026-10-13); the real
//    difference, if any, is physical, so the periphery is the IP's itself.
//
// A request runs the IP's states ONE..TEN for the six Avalon writes of the original
// table machine, cycle for cycle: for each of N, M and C0 the counter value (13h,
// 12h, C0's address), reads of the bypass register 15h and the odd-division register
// 17h, two idle cycles while the data arrive, then both registers written back with
// that counter's bit changed (N bypassed, M and C0 not, no odd division); then K: 17h
// read, written back with the K-ready bit 11 clear, K's low and high halves (18h,
// 19h), 17h with the ready bit set. The PLL relocks by itself. Idle cycles drive
// address, data and byte enables to zero, as the IP does. Finally the C0 register is
// read back at 00h and at 11h (rb_c0a, rb_c0b) for the test tools.
//
// DPRIO transactions are one clock wide; a read's data is on reconfig_from_pll[15:0]
// two clocks after the strobe. The sequencer's outputs are registered, so the bus
// runs one clock behind the step counter; the captures are placed accordingly.
module dot_pll_cfg
(
	input             clk,              // the PLL's management clock (50 MHz); it is also the DPRIO clock
	input             req,              // level: reconfigure to the values below (edge-detected)
	input       [7:0] c0_hi,            // C0 high and low counts (even divider: both div/2)
	input       [7:0] c0_lo,
	input      [31:0] m_frac,           // K: the fractional part of M, 32 bits
	output reg        busy,             // 1 from the request to the end of the sequence
	output            ready,            // 1 once the power-up initialization is over
	output            locked,           // the PLL's lock, synchronized
	output reg [15:0] rb_c0a,           // the C0 register read back at 00h after the last request
	output reg [15:0] rb_c0b,           // the same at 11h (the other half's map)
	output     [63:0] reconfig_to_pll,
	input      [63:0] reconfig_from_pll
);

localparam device_family = "Cyclone V";

// ---- the IP's periphery: reset timing, lock synchronizer, the DPRIO init block
wire        reset, dprio_init_reset;
self_reset self_reset_inst (.mgmt_reset(1'b0), .clk(clk), .reset(reset), .init_reset(dprio_init_reset));

wire        locked_orig = reconfig_from_pll[16];
altera_std_synchronizer #(.depth(3)) altera_std_synchronizer_inst (.clk(clk), .reset_n(1'b1), .din(locked_orig), .dout(locked));

wire  [5:0] init_dprio_address;
wire        init_dprio_read, init_dprio_write, init_atpgmode, init_mdio_dis, init_scanen, init_ser_shift_load, dprio_init_done;
wire  [1:0] init_dprio_byteen;
wire [15:0] init_dprio_writedata;
fpll_dprio_init fpll_dprio_init_inst (
	.clk(clk), .reset_n(~reset), .locked(locked),
	.dprio_address(init_dprio_address), .dprio_read(init_dprio_read), .dprio_byteen(init_dprio_byteen),
	.dprio_write(init_dprio_write), .dprio_writedata(init_dprio_writedata),
	.atpgmode(init_atpgmode), .mdio_dis(init_mdio_dis), .scanen(init_scanen), .ser_shift_load(init_ser_shift_load),
	.dprio_init_done(dprio_init_done));
assign ready = dprio_init_done;

// the half flag: the fitter rewrites this cell's mask for the second PLL of a DPRIO pair
wire fpll_1;
generic_lcell_comb lcell_fpll_0_1 (.dataa(1'b0), .combout(fpll_1));
defparam lcell_fpll_0_1.lut_mask = 64'hAAAAAAAAAAAAAAAA;
defparam lcell_fpll_0_1.dont_touch = "on";
defparam lcell_fpll_0_1.family = device_family;
reg   [5:0] c0_addr;                   // an if, as the IP: an open cell input simulates as X, which must not spread
always @* begin
	c0_addr = 6'h00;
	if (fpll_1) c0_addr = 6'h11;
end

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
		if (dprio_init_done && req && !req_d) begin
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
			6'd15: wr(c0_addr, {c0_hi_r, c0_lo_r});
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

// ---- the bus to the PLL: the IP's mux and its kept nets
wire  [5:0] dprio_address /*synthesis keep*/;
wire        dprio_read /*synthesis keep*/;
wire  [1:0] dprio_byteen /*synthesis keep*/;
wire        dprio_write /*synthesis keep*/;
wire [15:0] dprio_writedata /*synthesis keep*/;
wire        dprio_mdio_dis /*synthesis keep*/;
wire        dprio_ser_shift_load /*synthesis keep*/;
wire        dprio_atpgmode /*synthesis keep*/;
wire        dprio_scanen /*synthesis keep*/;
wire        phase_en /*synthesis keep*/;
wire        up_dn /*synthesis keep*/;
wire        gnd /*synthesis keep*/;
assign gnd = 1'b0;

dprio_mux dprio_mux_inst (
	.init_dprio_address(init_dprio_address), .init_dprio_read(init_dprio_read), .init_dprio_byteen(init_dprio_byteen),
	.init_dprio_write(init_dprio_write), .init_dprio_writedata(init_dprio_writedata),
	.init_atpgmode(init_atpgmode), .init_mdio_dis(init_mdio_dis), .init_scanen(init_scanen), .init_ser_shift_load(init_ser_shift_load),
	.dprio_init_done(dprio_init_done),
	.avmm_dprio_address(dp_addr), .avmm_dprio_read(dp_read), .avmm_dprio_byteen(dp_be),
	.avmm_dprio_write(dp_write), .avmm_dprio_writedata(dp_data),
	.avmm_atpgmode(1'b0), .avmm_mdio_dis(1'b0), .avmm_scanen(1'b0), .avmm_ser_shift_load(1'b1),
	.dprio_address(dprio_address), .dprio_read(dprio_read), .dprio_byteen(dprio_byteen),
	.dprio_write(dprio_write), .dprio_writedata(dprio_writedata),
	.atpgmode(dprio_atpgmode), .mdio_dis(dprio_mdio_dis), .scanen(dprio_scanen), .ser_shift_load(dprio_ser_shift_load));

// no dynamic phase shift: its registers at rest, kept as the IP keeps them
reg  [4:0] usr_cnt_sel /*synthesis preserve*/;
reg        usr_up_dn /*synthesis preserve*/;
reg        usr_phase_en /*synthesis preserve*/;
initial begin
	usr_cnt_sel  = 5'd0;
	usr_up_dn    = 1'b0;
	usr_phase_en = 1'b0;
end
always @(posedge clk) begin
	usr_cnt_sel  <= 5'd0;
	usr_up_dn    <= 1'b0;
	usr_phase_en <= 1'b0;
end
assign up_dn    = usr_up_dn;
assign phase_en = usr_phase_en;

wire  [4:0] cnt_sel;
generic_lcell_comb lcell_cnt_sel_0 (.dataa(usr_cnt_sel[0]), .datab(usr_cnt_sel[1]), .datac(usr_cnt_sel[2]), .datad(usr_cnt_sel[3]), .datae(usr_cnt_sel[4]), .dataf(gnd), .combout(cnt_sel[0]));
defparam lcell_cnt_sel_0.lut_mask = 64'hAAAAAAAAAAAAAAAA;
defparam lcell_cnt_sel_0.dont_touch = "on";
defparam lcell_cnt_sel_0.family = device_family;
generic_lcell_comb lcell_cnt_sel_1 (.dataa(usr_cnt_sel[0]), .datab(usr_cnt_sel[1]), .datac(usr_cnt_sel[2]), .datad(usr_cnt_sel[3]), .datae(usr_cnt_sel[4]), .dataf(gnd), .combout(cnt_sel[1]));
defparam lcell_cnt_sel_1.lut_mask = 64'hCCCCCCCCCCCCCCCC;
defparam lcell_cnt_sel_1.dont_touch = "on";
defparam lcell_cnt_sel_1.family = device_family;
generic_lcell_comb lcell_cnt_sel_2 (.dataa(usr_cnt_sel[0]), .datab(usr_cnt_sel[1]), .datac(usr_cnt_sel[2]), .datad(usr_cnt_sel[3]), .datae(usr_cnt_sel[4]), .dataf(gnd), .combout(cnt_sel[2]));
defparam lcell_cnt_sel_2.lut_mask = 64'hF0F0F0F0F0F0F0F0;
defparam lcell_cnt_sel_2.dont_touch = "on";
defparam lcell_cnt_sel_2.family = device_family;
generic_lcell_comb lcell_cnt_sel_3 (.dataa(usr_cnt_sel[0]), .datab(usr_cnt_sel[1]), .datac(usr_cnt_sel[2]), .datad(usr_cnt_sel[3]), .datae(usr_cnt_sel[4]), .dataf(gnd), .combout(cnt_sel[3]));
defparam lcell_cnt_sel_3.lut_mask = 64'hFF00FF00FF00FF00;
defparam lcell_cnt_sel_3.dont_touch = "on";
defparam lcell_cnt_sel_3.family = device_family;
generic_lcell_comb lcell_cnt_sel_4 (.dataa(usr_cnt_sel[0]), .datab(usr_cnt_sel[1]), .datac(usr_cnt_sel[2]), .datad(usr_cnt_sel[3]), .datae(usr_cnt_sel[4]), .dataf(gnd), .combout(cnt_sel[4]));
defparam lcell_cnt_sel_4.lut_mask = 64'hFFFF0000FFFF0000;
defparam lcell_cnt_sel_4.dont_touch = "on";
defparam lcell_cnt_sel_4.family = device_family;

// the read strobe through the IP's cell
wire        dprio_read_combout;
generic_lcell_comb lcell_dprio_read (.dataa(fpll_1), .datab(dprio_read), .datac(1'b0), .datad(1'b0), .datae(1'b0), .dataf(1'b0), .combout(dprio_read_combout));
defparam lcell_dprio_read.lut_mask = 64'hCCCCCCCCCCCCCCCC;
defparam lcell_dprio_read.dont_touch = "on";
defparam lcell_dprio_read.family = device_family;

assign reconfig_to_pll[0]     = clk;                                   // dprio_clk
assign reconfig_to_pll[1]     = ~dprio_init_reset;
assign reconfig_to_pll[2]     = dprio_write;
assign reconfig_to_pll[3]     = dprio_read_combout;
assign reconfig_to_pll[9:4]   = dprio_address;
assign reconfig_to_pll[25:10] = dprio_writedata;
assign reconfig_to_pll[27:26] = dprio_byteen;
assign reconfig_to_pll[28]    = dprio_ser_shift_load;
assign reconfig_to_pll[29]    = dprio_mdio_dis;
assign reconfig_to_pll[30]    = phase_en;
assign reconfig_to_pll[31]    = up_dn;
assign reconfig_to_pll[36:32] = cnt_sel;
assign reconfig_to_pll[37]    = dprio_scanen;
assign reconfig_to_pll[38]    = dprio_atpgmode;
assign reconfig_to_pll[63:39] = 25'd0;

endmodule
