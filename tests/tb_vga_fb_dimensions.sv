`timescale 1ns/1ps

module tb_vga_fb_dimensions;
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
    logic vga_border = 1;
    logic scanline_req_valid = 0;
    wire scanline_req_ready;
    logic scanline_frame_start = 0;
    logic [10:0] scanline_y = 0;
    wire [10:0] scanline_width;
    wire [10:0] scanline_height;
    wire [31:0] scanline_native_frames;
    wire scanline_done;

    always #5 clk_sys = ~clk_sys;
    always #7 clk_vga = ~clk_vga;

    vga #(.ONDEMAND_SCANOUT(1'b1)) dut (.*);

    task automatic check_dimensions;
        @(posedge clk_sys);
        #1;
        if (vga_width != 9'd128)
            $fatal(1, "1024-pixel framebuffer width includes overscan: %0d groups", vga_width);
        if (vga_height != 11'd768)
            $fatal(1, "768-line framebuffer height includes overscan: %0d", vga_height);
    endtask

    initial begin
        repeat (3) @(posedge clk_sys);
        rst_n = 1;

        force dut.crtc_horizontal_display_size = 8'd127;
        force dut.crtc_horizontal_blanking_start = 9'd127;
        force dut.horiz_overscan_left = 9'd2;
        force dut.crtc_vertical_display_size = 11'd767;
        force dut.crtc_vertical_blanking_start = 11'd767;
        force dut.vert_overscan_top = 11'd8;

        vga_border = 1;
        check_dimensions();
        vga_border = 0;
        check_dimensions();

        // The row interface reports logical pixels after VGA's built-in
        // dot-clock and doublescan replication has been removed.
        force dut.vga_width = 9'd80;
        force dut.vga_height = 11'd400;
        force dut.seq_8dot_char = 1'b0;
        force dut.seq_dotclock_divided = 1'b0;
        force dut.attrib_pelclock_div2 = 1'b0;
        force dut.vertical_doublescan = 1'b0;
        #1;
        if (scanline_width != 11'd720 || scanline_height != 11'd400)
            $fatal(1, "80-column text dimensions are %0dx%0d",
                   scanline_width, scanline_height);
        force dut.seq_8dot_char = 1'b1;
        #1;
        if (scanline_width != 11'd640)
            $fatal(1, "640-pixel planar width is %0d", scanline_width);
        force dut.seq_dotclock_divided = 1'b1;
        force dut.attrib_pelclock_div2 = 1'b1;
        force dut.vertical_doublescan = 1'b1;
        #1;
        if (scanline_width != 11'd320 || scanline_height != 11'd200)
            $fatal(1, "mode-13h logical dimensions are %0dx%0d",
                   scanline_width, scanline_height);

        release dut.vga_width;
        release dut.vga_height;
        release dut.vertical_doublescan;
        release dut.seq_8dot_char;
        release dut.seq_dotclock_divided;
        release dut.attrib_pelclock_div2;

        // The native CRTC must keep advancing while the pixel renderer is
        // idle, then the renderer must produce exactly the requested row and
        // return to idle without waiting for the programmed pixel enable.
        force dut.ce_video = 1'b1;
        force dut.seq_8dot_char = 1'b1;
        force dut.seq_dotclock_divided = 1'b0;
        force dut.attrib_pelclock_div2 = 1'b0;
        force dut.crtc_horizontal_total = 8'd7;
        force dut.crtc_horizontal_display_size = 8'd1;
        force dut.crtc_horizontal_blanking_start = 9'd2;
        force dut.crtc_horizontal_blanking_end = 6'd4;
        force dut.crtc_horizontal_retrace_start = 8'd4;
        force dut.crtc_horizontal_retrace_end = 5'd6;
        force dut.crtc_horizontal_retrace_skew = 2'd0;
        force dut.crtc_vertical_total = 11'd7;
        force dut.crtc_vertical_display_size = 11'd3;
        force dut.crtc_vertical_blanking_start = 11'd4;
        force dut.crtc_vertical_blanking_end = 8'd6;
        force dut.crtc_vertical_retrace_start = 11'd5;
        force dut.crtc_vertical_retrace_end = 4'd6;

        begin : check_ondemand
            integer native_before;
            integer renderer_before;
            integer timeout;
            integer active_pixels;

            repeat (200) @(posedge clk_vga);
            native_before = dut.native_vert_cnt;
            renderer_before = dut.vert_cnt;
            repeat (800) @(posedge clk_vga);
            if (dut.native_vert_cnt == native_before)
                $fatal(1, "native CRTC stopped while renderer was idle");
            if (dut.vert_cnt != renderer_before)
                $fatal(1, "on-demand renderer advanced without a request");

            wait (scanline_req_ready);
            scanline_y = 11'd2;
            scanline_frame_start = 1'b1;
            scanline_req_valid = 1'b1;
            @(posedge clk_vga);
            scanline_req_valid = 1'b0;
            scanline_frame_start = 1'b0;
            timeout = 0;
            active_pixels = 0;
            while (!scanline_done && timeout < 400) begin
                @(posedge clk_vga);
                if (vga_ce && vga_blank_n)
                    active_pixels = active_pixels + 1;
                timeout = timeout + 1;
            end
            if (!scanline_done)
                $fatal(1, "requested scanline did not complete");
            if (active_pixels == 0)
                $fatal(1, "requested scanline contained no active pixels");
            if (active_pixels < scanline_width)
                $fatal(1, "row emitted only %0d pixels, descriptor says %0d",
                       active_pixels, scanline_width);
            if (!scanline_req_ready)
                @(posedge clk_vga);
            if (!scanline_req_ready)
                $fatal(1, "renderer did not return to ready");
            if (scanline_native_frames == 0)
                $fatal(1, "native retrace counter did not advance");
        end

        // Mode 13h programs 400 physical CRTC lines by repeating each of the
        // 200 framebuffer rows. The row interface has already removed that
        // repeat, so adjacent requests must advance to adjacent source rows.
        force dut.crtc_row_max = 5'd1;
        force dut.crtc_vertical_doublescan = 1'b0;
        force dut.crtc_row_preset = 5'd0;
        force dut.crtc_address_start = 18'd0;
        force dut.crtc_address_byte_panning = 2'd0;
        force dut.crtc_address_offset = 9'd3;
        begin : check_doublescan_addressing
            integer timeout;
            integer first_row_address;
            integer second_row_address;

            wait (scanline_req_ready);
            scanline_y = 11'd0;
            scanline_frame_start = 1'b1;
            scanline_req_valid = 1'b1;
            @(posedge clk_vga);
            scanline_req_valid = 1'b0;
            scanline_frame_start = 1'b0;
            timeout = 0;
            while (!scanline_done && timeout < 400) begin
                @(posedge clk_vga);
                timeout = timeout + 1;
            end
            if (!scanline_done)
                $fatal(1, "first doublescan row did not complete");
            first_row_address = dut.memory_start_line;

            wait (scanline_req_ready);
            scanline_y = 11'd1;
            scanline_req_valid = 1'b1;
            @(posedge clk_vga);
            scanline_req_valid = 1'b0;
            timeout = 0;
            while (!scanline_done && timeout < 400) begin
                @(posedge clk_vga);
                timeout = timeout + 1;
            end
            if (!scanline_done)
                $fatal(1, "second doublescan row did not complete");
            second_row_address = dut.memory_start_line;
            if (second_row_address != first_row_address + 6)
                $fatal(1, "logical rows repeated source address %0h -> %0h",
                       first_row_address, second_row_address);
        end

        $display("PASS: SVGA dimensions and independent on-demand VGA row");
        $finish;
    end
endmodule
