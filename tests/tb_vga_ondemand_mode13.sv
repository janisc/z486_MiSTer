`timescale 1ns/1ps

module tb_vga_ondemand_mode13;
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

    vga #(.ONDEMAND_SCANOUT(1'b1)) dut (.*);

    initial begin : test
        integer i;
        integer timeout;
        integer pixels;
        integer row;
        integer request;
        integer warmup_pixels;
        reg [7:0] expected [0:3];

        expected[0] = 8'h10;
        expected[1] = 8'h40;
        expected[2] = 8'h80;
        expected[3] = 8'hc0;
        for (i = 0; i < 65536; i = i + 1) begin
            dut.plane_ram_0.default_ram.ram.mem[i] = expected[0];
            dut.plane_ram_1.default_ram.ram.mem[i] = expected[1];
            dut.plane_ram_2.default_ram.ram.mem[i] = expected[2];
            dut.plane_ram_3.default_ram.ram.mem[i] = expected[3];
        end
        for (i = 0; i < 256; i = i + 1)
            dut.dac_ram.mem[i] = {3{i[7:2]}};

        force dut.ce_video = 1'b1;
        force dut.seq_screen_disable = 1'b0;
        force dut.seq_8dot_char = 1'b1;
        force dut.seq_dotclock_divided = 1'b0;
        force dut.attrib_pelclock_div2 = 1'b1;
        force dut.attrib_graphic_mode = 1'b1;
        force dut.attrib_mask = 4'hf;
        force dut.attrib_blinking = 1'b0;
        force dut.attrib_pas = 1'b1;
        force dut.attrib_color_bit5_4_enable = 1'b0;
        force dut.graph_shift_mode = 2'd2;
        force dut.crtc_horizontal_total = 9'd7;
        force dut.crtc_horizontal_display_size = 8'd3;
        force dut.crtc_horizontal_blanking_start = 9'd4;
        force dut.crtc_horizontal_blanking_end = 6'd6;
        force dut.crtc_horizontal_retrace_start = 9'd5;
        force dut.crtc_horizontal_retrace_end = 5'd6;
        force dut.crtc_horizontal_retrace_skew = 2'd0;
        force dut.crtc_vertical_total = 11'd7;
        force dut.crtc_vertical_display_size = 11'd3;
        force dut.crtc_vertical_blanking_start = 11'd4;
        force dut.crtc_vertical_blanking_end = 8'd6;
        force dut.crtc_vertical_retrace_start = 11'd5;
        force dut.crtc_vertical_retrace_end = 4'd6;
        force dut.crtc_row_max = 5'd1;
        force dut.crtc_vertical_doublescan = 1'b0;
        force dut.crtc_row_preset = 5'd0;
        force dut.crtc_address_start = 20'd0;
        force dut.crtc_address_byte_panning = 2'd0;
        force dut.crtc_address_offset = 9'd2;
        force dut.crtc_address_doubleword = 1'b1;
        force dut.crtc_address_bit13 = 1'b1;
        force dut.crtc_address_bit14 = 1'b1;
        force dut.memory_panning_reg = 4'd0;

        repeat (4) @(posedge clk_sys);
        rst_n = 1'b1;
        repeat (8) @(posedge clk_sys);

        for (request = 0; request < 8; request = request + 1) begin
            row = request & 3;
            wait (scanline_req_ready);
            scanline_y = row[10:0];
            scanline_frame_start = row == 0;
            scanline_req_valid = 1'b1;
            @(posedge clk_vga);
            scanline_req_valid = 1'b0;
            scanline_frame_start = 1'b0;

            timeout = 0;
            pixels = 0;
            warmup_pixels = request == 0 ? 3 : 0;
            while (!scanline_done && timeout < 400) begin
                @(posedge clk_vga);
                if (vga_ce && vga_blank_n) begin
                    if (pixels >= warmup_pixels &&
                        pixels < warmup_pixels + 16 &&
                        vga_r != {expected[(pixels-warmup_pixels) & 3][7:2],
                                  expected[(pixels-warmup_pixels) & 3][7:6]})
                        $fatal(1, "row %0d pixel %0d phase mismatch", row, pixels);
                    pixels = pixels + 1;
                end
                timeout = timeout + 1;
            end
            if (!scanline_done)
                $fatal(1, "mode-13h row %0d did not complete", row);
            if (pixels != 16 + warmup_pixels)
                $fatal(1, "mode-13h row %0d emitted %0d pixels instead of %0d",
                       row, pixels, 16 + warmup_pixels);
        end

        $display("PASS: consecutive on-demand mode-13h pixel rows");
        $finish;
    end
endmodule
