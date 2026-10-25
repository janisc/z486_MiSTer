// ao486-compatible SYSCTL writes and versioned z486 speed capabilities.
module sysctl (
    input  logic       clk,
    input  logic       reset,
    input  logic [2:0] io_address,   // Offset within 8888h..888Fh.
    input  logic       io_write,
    input  logic       io_cs,
    input  logic [7:0] io_writedata,
    output logic [7:0] io_readdata,
    input  logic [2:0] osd_speed,    // Full/56/30/15/6/5/4/3.
    output logic [2:0] speed_sel,    // Full/15/30/56/6/5/4/3 (SYSCTL order).
    output logic [7:0] control = 8'd0
);

logic [7:0] pending_control;
wire [2:0] osd_sel = osd_speed[2] ? osd_speed :
                     {1'b0, osd_speed[1] ^ osd_speed[0], osd_speed[0]};
assign speed_sel = control[7] ? control[2:0] : osd_sel;

always_comb begin
    case (io_address)
        3'd0: io_readdata = control;
        3'd1: io_readdata = 8'ha1; // Original OUTW commit signature.
        3'd2: io_readdata = 8'h5a; // "Z486": identify the platform, not CPUID.
        3'd3: io_readdata = 8'h34;
        3'd4: io_readdata = 8'h38;
        3'd5: io_readdata = 8'h36;
        3'd6: io_readdata = 8'd1;  // Capability ABI revision, not release date.
        default: io_readdata = 8'hff; // Speed-selector support mask (all eight).
    endcase
end

always_ff @(posedge clk) begin
    if (reset) begin
        control <= 8'd0;
        pending_control <= 8'd0;
    end else if (io_cs && io_write) begin
        if (io_address == 3'd0)
            pending_control <= io_writedata;
        else if ((io_address == 3'd1) && (io_writedata == 8'ha1))
            control <= pending_control;
    end
end

endmodule
