// `timescale 1ns / 1ps

module synchronizer #(
    parameter DATA_WIDTH = 1
) (
    input clk,   // clock domain of out
    input [DATA_WIDTH-1:0] in,
    output reg [DATA_WIDTH-1:0] out
);
    // Preserve both stages as colocated synchronizer registers.  In
    // particular, Vivado must not replace this chain with an SRL.
    (* ASYNC_REG = "TRUE" *) logic [1:0] [DATA_WIDTH-1:0] sync_regs = 0;

    always_ff @(posedge clk)
    	{sync_regs[1], sync_regs[0]} <= {sync_regs[0], in};

    always_comb out = sync_regs[1];
endmodule
