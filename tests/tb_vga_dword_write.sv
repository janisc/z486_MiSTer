`timescale 1ns/1ps

// A chain-4 dword write stores bytes 0-3 in planes 0-3 at one plane address,
// as four byte writes do, and only while the graphics controller passes host
// data unchanged.
module tb_vga_dword_write;
    logic clk_sys = 0;
    logic clk_vga = 0;
    logic rst_n = 0;
    logic [3:0] io_address = 0;
    logic io_read = 0;
    wire [7:0] io_readdata;
    logic io_write = 0;
    logic [7:0] io_writedata = 0;
    logic io_b_cs = 0;
    logic io_c_cs = 0;
    logic io_d_cs = 0;
    logic [16:0] mem_address = 0;
    logic mem_read = 0;
    wire [7:0] mem_readdata;
    logic mem_write = 0;
    logic [7:0] mem_writedata = 0;
    logic mem_write_dword = 0;
    logic [31:0] mem_writedata_dword = 0;
    wire mem_dword_write_ok;
    wire irq;
    logic [27:0] clock_rate_vga = 28'd25_175_000;
    wire vga_ce;
    logic vga_f60 = 0;
    wire [2:0] vga_memmode;
    wire vga_blank_n;
    wire vga_off;
    wire vga_horiz_sync;
    wire vga_vert_sync;
    wire [7:0] vga_r;
    wire [7:0] vga_g;
    wire [7:0] vga_b;
    wire [17:0] vga_pal_d;
    wire [7:0] vga_pal_a;
    wire vga_pal_we;
    wire [19:0] vga_start_addr;
    wire [5:0] vga_wr_seg;
    wire [5:0] vga_rd_seg;
    wire [8:0] vga_width;
    wire [8:0] vga_stride;
    wire [10:0] vga_height;
    wire [3:0] vga_flags;
    wire vga_chain4;
    wire [3:0] vga_map_mask;
    wire [1:0] vga_read_plane;
    wire [1:0] vga_write_mode;
    logic vga_lores = 1;
    logic vga_border = 0;
    logic scanline_req_valid = 0;
    wire scanline_req_ready;
    logic scanline_frame_start = 0;
    logic [10:0] scanline_y = 0;
    wire [10:0] scanline_width;
    wire [10:0] scanline_height;
    wire [31:0] scanline_native_frames;
    wire scanline_done;

    always #5 clk_sys = ~clk_sys;
    assign clk_vga = clk_sys;

    vga dut (.*);

    function automatic [31:0] plane_word(input integer a);
        plane_word = {dut.plane_ram_3.default_ram.ram.mem[a], dut.plane_ram_2.default_ram.ram.mem[a],
                      dut.plane_ram_1.default_ram.ram.mem[a], dut.plane_ram_0.default_ram.ram.mem[a]};
    endfunction

    task automatic byte_write(input [16:0] a, input [7:0] d);
        mem_address = a; mem_writedata = d; mem_write = 1'b1;
        @(posedge clk_sys); mem_write = 1'b0; @(posedge clk_sys);
    endtask

    task automatic dword_write(input [16:0] a, input [31:0] d);
        mem_address = a; mem_writedata_dword = d; mem_write_dword = 1'b1;
        @(posedge clk_sys); mem_write_dword = 1'b0; @(posedge clk_sys);
    endtask

    initial begin : test
        integer i;
        for (i = 0; i < 65536; i = i + 1) begin
            dut.plane_ram_0.default_ram.ram.mem[i] = 8'h00;
            dut.plane_ram_1.default_ram.ram.mem[i] = 8'h00;
            dut.plane_ram_2.default_ram.ram.mem[i] = 8'h00;
            dut.plane_ram_3.default_ram.ram.mem[i] = 8'h00;
        end
        repeat (4) @(posedge clk_sys);
        rst_n = 1'b1;
        repeat (4) @(posedge clk_sys);
        // Mode 13h: chain 4, all maps enabled, write mode 0 identity.
        force dut.general_enable_ram = 1'b1;
        force dut.seq_access_chain4 = 1'b1;
        force dut.seq_map_write_enable = 4'hF;
        force dut.graph_write_mode = 2'd0;
        force dut.graph_write_rotate = 3'd0;
        force dut.graph_write_function = 2'd0;
        force dut.graph_write_enable_map = 4'h0;
        force dut.graph_write_mask = 8'hFF;
        @(posedge clk_sys);
        if (!mem_dword_write_ok) $fatal(1, "identity chain-4 state does not allow dword writes");

        dword_write(17'h01234, 32'hDDCCBBAA);
        byte_write(17'h01238, 8'h11); byte_write(17'h01239, 8'h22);
        byte_write(17'h0123A, 8'h33); byte_write(17'h0123B, 8'h44);
        if (plane_word(16'h1234) !== 32'hDDCCBBAA)
            $fatal(1, "dword write: planes hold %08x", plane_word(16'h1234));
        if (plane_word(16'h1238) !== 32'h44332211)
            $fatal(1, "byte writes: planes hold %08x", plane_word(16'h1238));

        // The map mask still selects planes.
        force dut.seq_map_write_enable = 4'b0101;
        dword_write(17'h01234, 32'h99887766);
        if (plane_word(16'h1234) !== 32'hDD88BB66)
            $fatal(1, "map-masked dword write: planes hold %08x", plane_word(16'h1234));

        // Any graphics-controller processing disables the dword path.
        force dut.graph_write_mask = 8'h0F; @(posedge clk_sys);
        if (mem_dword_write_ok) $fatal(1, "bit mask did not disable dword writes");
        force dut.graph_write_mask = 8'hFF; force dut.graph_write_mode = 2'd1; @(posedge clk_sys);
        if (mem_dword_write_ok) $fatal(1, "write mode 1 did not disable dword writes");
        force dut.graph_write_mode = 2'd0; force dut.seq_access_chain4 = 1'b0; @(posedge clk_sys);
        if (mem_dword_write_ok) $fatal(1, "planar mode did not disable dword writes");

        $display("PASS: chain-4 dword VGA writes match byte writes");
        $finish;
    end
endmodule
