// Single-port block RAM as the GF1 model instantiates it: spram #(address width, data width).
// Same altsyncram settings as the spram entity of the MiSTer cores' bram.vhd (registered
// address, unregistered output, new data on a read during a write), written in Verilog because
// that VHDL file also defines a dpram entity, which this core already has as a Verilog module.

module spram #(parameter addr_width = 8, parameter data_width = 8)
(
	input                   clock,
	input  [addr_width-1:0] address,
	input  [data_width-1:0] data,
	input                   wren,
	output [data_width-1:0] q
);

altsyncram #(
	.clock_enable_input_a          ("BYPASS"),
	.clock_enable_output_a         ("BYPASS"),
	.intended_device_family        ("Cyclone V"),
	.lpm_type                      ("altsyncram"),
	.numwords_a                    (1 << addr_width),
	.operation_mode                ("SINGLE_PORT"),
	.outdata_aclr_a                ("NONE"),
	.outdata_reg_a                 ("UNREGISTERED"),
	.power_up_uninitialized        ("FALSE"),
	.read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
	.widthad_a                     (addr_width),
	.width_a                       (data_width),
	.width_byteena_a               (1)
) ram (
	.address_a      (address),
	.clock0         (clock),
	.data_a         (data),
	.wren_a         (wren),
	.q_a            (q),
	.aclr0          (1'b0),
	.aclr1          (1'b0),
	.address_b      (1'b1),
	.addressstall_a (1'b0),
	.addressstall_b (1'b0),
	.byteena_a      (1'b1),
	.byteena_b      (1'b1),
	.clock1         (1'b1),
	.clocken0       (1'b1),
	.clocken1       (1'b1),
	.clocken2       (1'b1),
	.clocken3       (1'b1),
	.data_b         (1'b1),
	.eccstatus      (),
	.q_b            (),
	.rden_a         (1'b1),
	.rden_b         (1'b1),
	.wren_b         (1'b0)
);

endmodule
