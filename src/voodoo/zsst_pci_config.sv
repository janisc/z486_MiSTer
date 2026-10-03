// Minimal PCI configuration mechanism #1 endpoint for an SST-1 card.
//
// The PC accesses 0xcf8/0xcfc through z486's byte peripheral bus.  This is
// intentionally only the configuration mechanism, not a general PCI bus: the
// enabled BAR is routed directly to zSST by system.sv.
`timescale 1ns/1ns

module zsst_pci_config #(
    parameter logic [7:0]  BUS_NUMBER      = 8'd0,
    parameter logic [4:0]  DEVICE_NUMBER   = 5'd5,
    parameter logic [2:0]  FUNCTION_NUMBER = 3'd0,
    // The PC BIOS does not enumerate this synthetic PCI function. Model the
    // firmware-assigned resources that a physical SST-1 receives before DOS.
    parameter logic [7:0]  RESET_BAR0_HIGH = 8'he0,
    parameter logic        RESET_MEMORY_ENABLE = 1'b1
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [15:0] io_address,
    input  logic        io_read,
    input  logic        io_write,
    input  logic [7:0]  io_writedata,
    output logic [7:0]  io_readdata,
    output logic        io_chip_select,
    output logic        memory_enable,
    output logic [31:0] bar0_base,
    output logic [31:0] init_enable
);

logic [31:0] config_address;
logic [7:0] bar0_high;

wire config_address_port = (io_address >= 16'h0cf8) &&
                           (io_address <= 16'h0cfb);
wire config_data_port = (io_address >= 16'h0cfc) &&
                        (io_address <= 16'h0cff);
wire function_selected = config_address[31] &&
                         config_address[23:16] == BUS_NUMBER &&
                         config_address[15:11] == DEVICE_NUMBER &&
                         config_address[10:8] == FUNCTION_NUMBER;
wire [7:0] config_offset = {config_address[7:2], io_address[1:0]};

assign io_chip_select = config_address_port || config_data_port;
assign bar0_base = {bar0_high, 24'h000000};

function automatic logic [7:0] config_read_byte(input logic [7:0] offset);
    begin
        case (offset)
            8'h00: config_read_byte = 8'h1a; // vendor 0x121a
            8'h01: config_read_byte = 8'h12;
            8'h02: config_read_byte = 8'h01; // SST-1 device 0x0001
            8'h03: config_read_byte = 8'h00;
            8'h04: config_read_byte = {6'd0, memory_enable, 1'b0};
            8'h05: config_read_byte = 8'h00;
            8'h06: config_read_byte = 8'h00;
            8'h07: config_read_byte = 8'h00;
            8'h08: config_read_byte = 8'h02; // FBI revision
            8'h09: config_read_byte = 8'h00; // programming interface
            8'h0a: config_read_byte = 8'h00; // subclass
            8'h0b: config_read_byte = 8'h04; // multimedia video device
            8'h0c: config_read_byte = 8'h00;
            8'h0d: config_read_byte = 8'h00;
            8'h0e: config_read_byte = 8'h00; // normal header
            8'h0f: config_read_byte = 8'h00;
            8'h10: config_read_byte = 8'h00; // 16 MiB memory BAR
            8'h11: config_read_byte = 8'h00;
            8'h12: config_read_byte = 8'h00;
            8'h13: config_read_byte = bar0_high;
            8'h40: config_read_byte = init_enable[7:0];
            8'h41: config_read_byte = init_enable[15:8];
            8'h42: config_read_byte = init_enable[23:16];
            8'h43: config_read_byte = init_enable[31:24];
            default: config_read_byte = 8'h00;
        endcase
    end
endfunction

always_ff @(posedge clk) begin
    if (!reset_n) begin
        config_address <= 32'd0;
        io_readdata <= 8'hff;
        memory_enable <= RESET_MEMORY_ENABLE;
        bar0_high <= RESET_BAR0_HIGH;
        init_enable <= 32'd0;
    end else begin
        if (io_write && config_address_port)
            config_address[8 * io_address[1:0] +: 8] <= io_writedata;

        if (io_write && config_data_port && function_selected) begin
            case (config_offset)
                8'h04: memory_enable <= io_writedata[1];
                // SST-1 implements a naturally aligned 16 MiB BAR, so only
                // the high address byte is writable.  Writing all ones reads
                // back as 0xff000000, the standard BAR size probe response.
                8'h13: bar0_high <= io_writedata;
                8'h40: init_enable[7:0] <= io_writedata;
                8'h41: init_enable[15:8] <= io_writedata;
                8'h42: init_enable[23:16] <= io_writedata;
                8'h43: init_enable[31:24] <= io_writedata;
                default: begin end
            endcase
        end

        if (io_read) begin
            if (config_address_port)
                io_readdata <= config_address[8 * io_address[1:0] +: 8];
            else if (config_data_port && function_selected)
                io_readdata <= config_read_byte(config_offset);
            else
                io_readdata <= 8'hff;
        end
    end
end

endmodule
