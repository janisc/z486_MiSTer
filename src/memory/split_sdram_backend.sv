// DE10-Nano/legacy-simulation guest-memory backend.
//
// This is intentionally outside system.sv: physical SDRAM is the special
// DE10 deployment, while the portable PC and KV260 use abstract request ports.
module split_sdram_backend #(
    parameter FREQ = 50_000_000,
    parameter HAS_DQM = 1'b1,
    parameter FAST_GRADE = 1'b1
) (
    input         clk,
    input         reset,
    input         refresh_allowed,
    input  [1:0]  sdram_size,
    output        busy,

    input         mem0_valid,
    output        mem0_ready,
    input         mem0_write,
    input  [31:0] mem0_addr,
    input  [31:0] mem0_din,
    output [31:0] mem0_dout,
    output        mem0_resp_valid,
    input   [3:0] mem0_be,
    input   [7:0] mem0_burstcount,

    input         mem1_valid,
    output        mem1_ready,
    input         mem1_write,
    input  [31:0] mem1_addr,
    input  [31:0] mem1_din,
    output [31:0] mem1_dout,
    output        mem1_resp_valid,
    input   [3:0] mem1_be,
    input   [7:0] mem1_burstcount,

    inout  [15:0] sdram_dq,
    output [12:0] sdram_a,
    output  [1:0] sdram_ba,
    output  [1:0] sdram_dqm,
    output        sdram_nwe,
    output        sdram_nras,
    output        sdram_ncas,
    output        sdram_ncs,
    output        sdram_cke
);

sdram #(
    .FREQ(FREQ),
    .HAS_DQM(HAS_DQM),
    .FAST_GRADE(FAST_GRADE)
) memory (
    .clk(clk),
    .nce(1'b0),
    .resetn(~reset),
    .refresh_allowed(refresh_allowed),
    .busy(busy),
    .sdram_size(sdram_size),

    .valid0(mem0_valid),
    .ready0(mem0_ready),
    .wr0(mem0_write),
    // The legacy controller calls this a word address in some comments, but
    // its interface and original system.sv connection carry a byte address;
    // bits 1:0 are ignored internally.
    .addr0(mem0_addr[26:0]),
    .din0(mem0_din),
    .dout0(mem0_dout),
    .resp_valid0(mem0_resp_valid),
    .be0(mem0_be),
    .burst_cnt0(mem0_burstcount[3:0]),
    .burst_done0(),

    .valid1(mem1_valid),
    .ready1(mem1_ready),
    .wr1(mem1_write),
    .addr1(mem1_addr[26:0]),
    .din1(mem1_din),
    .dout1(mem1_dout),
    .resp_valid1(mem1_resp_valid),
    .be1(mem1_be),
    .burst_cnt1(mem1_burstcount[3:0]),
    .burst_done1(),

    .valid2(1'b0),
    .ready2(),
    .wr2(1'b0),
    .addr2(27'd0),
    .din2(32'd0),
    .dout2(),
    .resp_valid2(),
    .be2(4'd0),
    .burst_cnt2(4'd0),
    .burst_done2(),

    .SDRAM_DQ(sdram_dq),
    .SDRAM_A(sdram_a),
    .SDRAM_DQM(sdram_dqm),
    .SDRAM_BA(sdram_ba),
    .SDRAM_nWE(sdram_nwe),
    .SDRAM_nRAS(sdram_nras),
    .SDRAM_nCAS(sdram_ncas),
    .SDRAM_nCS(sdram_ncs),
    .SDRAM_CKE(sdram_cke)
);

endmodule
