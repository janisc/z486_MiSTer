`timescale 1ns/1ps
// Where the native raster puts the picture against the hsync, per BIOS mode (issue #2).
//
// Programs the VGA block through its I/O ports with IBM's register sets and measures, on two
// lines in the middle of the picture, in dots from the hsync leading edge: the sync width, where
// the picture window (vga_blank_n) opens and closes, and the line length. Checked against what a
// real card does with the same registers (a pipeline of two character clocks in graphics modes,
// three in text): the picture 144 dots after the sync's leading edge in every graphics mode and
// 162 in text, in the 80- and the 40-column sets alike, which makes the back porch 48 / 54 dots,
// and 32 / 36 in the 40-column modes with their longer sync. The VGA BIOS's 24 bpp mode (112h, one byte
// per dot, three dots a pixel) is checked in its own dots: the picture 417 tripled dots after the sync's
// leading edge, 139 pixels. Also checked: the overscan colour
// and pel panning do not move the window, and with the border shown it is 8 dots a side (16 in
// the 40-column modes), all of it outside the sync.
//
// Run it from this folder with Verilator, like the other VGA benches here:
//   $ verilator --binary --timing -Wno-fatal --Mdir obj_dir/vga_porch --top-module tb_vga_porch \
//       tb_vga_porch.sv ../src/soc/vga.v ../src/soc/dotclk_ce.v ../src/common/dpram.v -o ../Vtb_vga_porch
//   $ ./obj_dir/Vtb_vga_porch
//
// Up to release 16 this printed 137 (13h, 12h, 10h), 129 (0Dh, 04h: back porch 17 dots), 154 (text)
// and 145 (40-column text), and 441 for 112h.
module tb_vga_porch;
    logic clk_sys = 0; wire clk_vga = clk_sys;
    logic rst_n = 0;
    logic [3:0] io_address = 0; logic io_read = 0; wire [7:0] io_readdata; logic io_write = 0; logic [7:0] io_writedata = 0;
    logic io_b_cs = 0, io_c_cs = 0, io_d_cs = 0;
    logic [16:0] mem_address = 0; logic mem_read = 0; wire [7:0] mem_readdata; logic mem_write = 0; logic [7:0] mem_writedata = 0;
    logic mem_write_dword = 0; logic [31:0] mem_writedata_dword = 0; wire mem_dword_write_ok;
    wire irq;
    logic [27:0] clock_rate_vga = 28'd25_175_000;   // = the dot rate: one dot per clock (the counts are in dots anyway)
    logic dotclk = 0, dotclk_valid = 0;
    wire [2:0] vga_dot_rate; wire vga_dot_slaved;
    wire vga_ce, vga_dot_ce;
    logic vga_f60 = 0;
    wire [2:0] vga_memmode; wire vga_blank_n, vga_off, vga_horiz_sync, vga_vert_sync, vga_hsync_neg, vga_vsync_neg;
    wire [7:0] vga_r, vga_g, vga_b; wire [17:0] vga_pal_d; wire [7:0] vga_pal_a; wire vga_pal_we, vga_dac_565;
    wire [19:0] vga_start_addr; wire [5:0] vga_wr_seg, vga_rd_seg; wire [8:0] vga_width, vga_stride; wire [10:0] vga_height;
    wire [3:0] vga_flags; wire vga_chain4; wire [3:0] vga_map_mask; wire [1:0] vga_read_plane, vga_write_mode;
    logic vga_lores = 0, vga_border = 0, vga_tvmode = 0, vga_vstretch = 0, vga_vzoom = 0, vga_vodd = 0;
    wire vga_lf_ce, vga_lf_nd, vga_lf_vsync, vga_lf_doublescan, vga_lf_dotdiv, vga_lf_rep2;
    logic fb_native = 0; logic [7:0] fb_pixel = 0; logic fb_native16 = 0, fb_native24 = 0; logic [23:0] fb_rgb = 0; logic fb_pix_ce = 0;
    logic scanline_req_valid = 0; wire scanline_req_ready; logic scanline_frame_start = 0; logic [10:0] scanline_y = 0;
    wire [10:0] scanline_width, scanline_height; wire [31:0] scanline_native_frames; wire scanline_done;

    always #5 clk_sys = ~clk_sys;
    vga dut (.*);

    task automatic outp(input [11:0] port, input [7:0] d);
        io_b_cs = (port[11:4] == 8'h3B); io_c_cs = (port[11:4] == 8'h3C); io_d_cs = (port[11:4] == 8'h3D);
        io_address = port[3:0]; io_writedata = d; io_write = 1'b1;
        @(posedge clk_sys); #1; io_write = 1'b0; io_b_cs = 0; io_c_cs = 0; io_d_cs = 0;
        @(posedge clk_sys); #1;
    endtask
    task automatic inp(input [11:0] port);
        io_b_cs = (port[11:4] == 8'h3B); io_c_cs = (port[11:4] == 8'h3C); io_d_cs = (port[11:4] == 8'h3D);
        io_address = port[3:0]; io_read = 1'b1;
        @(posedge clk_sys); #1; io_read = 1'b0; io_b_cs = 0; io_c_cs = 0; io_d_cs = 0;
        @(posedge clk_sys); #1; @(posedge clk_sys); #1;
    endtask

    // IBM's register sets: misc, sequencer 1..4, CRTC 0..18h, graphics 0..8, attribute 10h..14h
    reg [7:0] crtc [0:24]; reg [7:0] seqr [1:4]; reg [7:0] gfx [0:8]; reg [7:0] atc [16:20]; reg [7:0] misc;
    reg [199:0] crtc_v;
    task automatic load_tables(input integer mode);
        integer i;
        case (mode)
        'h13: begin misc = 8'h63; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h01_0F_00_0E;
              crtc_v = 200'h5F_4F_50_82_54_80_BF_1F_00_41_00_00_00_00_00_00_9C_8E_8F_28_40_96_B9_A3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_40_05_0F_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h41_00_0F_00_00; end
        'h0D: begin misc = 8'h63; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h09_0F_00_06;
              crtc_v = 200'h2D_27_28_90_2B_80_BF_1F_00_C0_00_00_00_00_00_00_9C_8E_8F_14_00_96_B9_E3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_00_05_0F_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h01_00_0F_00_00; end
        'h04: begin misc = 8'h63; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h09_03_00_02;
              crtc_v = 200'h2D_27_28_90_2B_80_BF_1F_00_C1_00_00_00_00_00_00_9C_8E_8F_14_00_96_B9_A2_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_30_0F_00_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h01_00_03_00_00; end
        'h10: begin misc = 8'hA3; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h01_0F_00_06;
              crtc_v = 200'h5F_4F_50_82_54_80_BF_1F_00_40_00_00_00_00_00_00_83_85_5D_28_0F_63_BA_E3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_00_05_0F_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h01_00_0F_00_00; end
        'h12: begin misc = 8'hE3; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h01_0F_00_06;
              crtc_v = 200'h5F_4F_50_82_54_80_0B_3E_00_40_00_00_00_00_00_00_EA_8C_DF_28_00_E7_04_E3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_00_05_0F_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h01_00_0F_00_00; end
        'h03: begin misc = 8'h67; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h00_03_00_02;
              crtc_v = 200'h5F_4F_50_82_55_81_BF_1F_00_4F_0D_0E_00_00_00_00_9C_8E_8F_28_1F_96_B9_A3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_10_0E_00_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h0C_00_0F_08_00; end
        'h01: begin misc = 8'h67; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h08_03_00_02;
              crtc_v = 200'h2D_27_28_90_2B_A0_BF_1F_00_4F_0D_0E_00_00_00_00_9C_8E_8F_14_1F_96_B9_A3_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_10_0E_00_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h0C_00_0F_08_00; end
        'h112: begin misc = 8'hEF; {seqr[1],seqr[2],seqr[3],seqr[4]} = 32'h01_0F_00_0E;   // the VGA BIOS's VBE mode, as MODEDUMP reads it
              crtc_v = 200'h25_EF_F2_86_F7_B7_0B_3E_00_40_00_00_84_00_00_00_EA_8C_DF_F0_60_E7_04_AB_FF;
              {gfx[0],gfx[1],gfx[2],gfx[3],gfx[4],gfx[5],gfx[6],gfx[7],gfx[8]} = 72'h00_00_00_00_00_40_05_0F_FF;
              {atc[16],atc[17],atc[18],atc[19],atc[20]} = 40'h01_00_0F_00_00; end
        default: $fatal(1, "no table for mode %0h", mode);
        endcase
        for (i = 0; i < 25; i = i + 1) crtc[i] = crtc_v[(24 - i) * 8 +: 8];
    endtask

    task automatic set_mode(input integer mode, input [7:0] overscan, input [3:0] pan);
        integer i;
        load_tables(mode);
        outp(12'h3C2, misc);
        outp(12'h3C4, 8'h00); outp(12'h3C5, 8'h01);
        for (i = 1; i <= 4; i = i + 1) begin outp(12'h3C4, i[7:0]); outp(12'h3C5, seqr[i]); end
        outp(12'h3C4, 8'h00); outp(12'h3C5, 8'h03);
        outp(12'h3D4, 8'h11); outp(12'h3D5, 8'h00);              // unprotect CRTC 0..7
        for (i = 0; i < 25; i = i + 1) begin outp(12'h3D4, i[7:0]); outp(12'h3D5, crtc[i]); end
        outp(12'h3D4, 8'h3F); outp(12'h3D5, (mode == 'h112) ? 8'h01 : 8'h00);   // horizontal total bit 8 (298 characters in 24 bpp)
        fb_native = (mode == 'h112); fb_native16 = (mode == 'h112); fb_native24 = (mode == 'h112); fb_rgb = 24'hFFFFFF;
        for (i = 0; i < 9; i = i + 1) begin outp(12'h3CE, i[7:0]); outp(12'h3CF, gfx[i]); end
        inp(12'h3DA);                                            // attribute flip-flop to "index"
        for (i = 0; i < 16; i = i + 1) begin outp(12'h3C0, i[7:0]); outp(12'h3C0, (mode == 'h13) ? i[7:0] : (i < 8 ? i[7:0] : (8'h10 + i[7:0] - 8'd8))); end
        for (i = 16; i <= 20; i = i + 1) begin
            outp(12'h3C0, i[7:0]);
            outp(12'h3C0, (i == 17) ? overscan : (i == 19) ? {4'd0, pan} : atc[i]);
        end
        outp(12'h3C0, 8'h20);                                    // palette address source on
    endtask

    // ---- measurement, one sample per dot
    integer pos = 0, lines_after_vs = 0, armed = 0, printed = 0, errors = 0;
    integer se_pos, de_on, de_off;
    integer x_line, x_sync, x_on, x_off;
    reg hs_prev = 0, bl_prev = 0, vs_prev = 0, vs_seen = 0;
    wire hs_a = (vga_horiz_sync != vga_hsync_neg);
    wire vs_a = (vga_vert_sync != vga_vsync_neg);
    reg [8*34:1] label;
    always @(posedge clk_vga) if (vga_dot_ce) begin
        if (vs_a && !vs_prev) vs_seen = 1;
        if (hs_a && !hs_prev) begin
            if (!vga_blank_n && bl_prev) de_off = pos + 1;       // the window closes on the sync's first dot
            if (armed && lines_after_vs >= 200 && printed < 2) begin
                if (printed == 0)
                    $display("  %0s: line %0d, sync %0d, picture window %0d..%0d (back porch %0d, front porch %0d)",
                             label, pos + 1, se_pos, de_on, de_off, de_on - se_pos, pos + 1 - de_off);
                if (pos + 1 != x_line || se_pos != x_sync || de_on != x_on || de_off != x_off) begin
                    $display("    FAIL: expected line %0d, sync %0d, window %0d..%0d", x_line, x_sync, x_on, x_off);
                    errors = errors + 1;
                end
                printed = printed + 1;
            end
            if (vs_seen) begin lines_after_vs = 0; vs_seen = 0; end else lines_after_vs = lines_after_vs + 1;
            pos = 0; se_pos = -1; de_on = -1; de_off = -1;
        end
        else begin
            pos = pos + 1;
            if (!hs_a && hs_prev) se_pos = pos;
            if (vga_blank_n && !bl_prev) de_on = pos;
            if (!vga_blank_n && bl_prev) de_off = pos;
        end
        hs_prev <= hs_a; bl_prev <= vga_blank_n; vs_prev <= vs_a;
    end

    task automatic run_case(input [8*34:1] name, input integer mode, input border, input [7:0] overscan, input [3:0] pan,
                            input integer e_line, input integer e_sync, input integer e_on, input integer e_off);
        vga_border = border;
        set_mode(mode, overscan, pan);
        label = name; printed = 0; armed = 0;
        x_line = e_line; x_sync = e_sync; x_on = e_on; x_off = e_off;
        repeat (3) @(posedge vs_a);       // frames to settle
        @(posedge clk_vga); wait (lines_after_vs == 10); armed = 1;
        wait (printed == 2);
        armed = 0;
    endtask

    initial begin : main
        integer i;
        for (i = 0; i < 65536; i = i + 1) begin
            dut.plane_ram_0.default_ram.ram.mem[i] = 8'hFF; dut.plane_ram_1.default_ram.ram.mem[i] = 8'hFF;
            dut.plane_ram_2.default_ram.ram.mem[i] = 8'hFF; dut.plane_ram_3.default_ram.ram.mem[i] = 8'hFF;
        end
        dut.dac_ram.mem[0] = 18'd0;
        for (i = 1; i < 256; i = i + 1) dut.dac_ram.mem[i] = 18'h3FFFF;
        repeat (8) @(posedge clk_sys); rst_n = 1'b1; repeat (8) @(posedge clk_sys); #1;

        $display("dots from the hsync leading edge");
        //                                         mode  border overscan pan   line sync  on  off
        run_case("13h",                            'h13, 0, 8'h00, 4'd0,  800,  96, 144, 784);
        run_case("12h",                            'h12, 0, 8'h00, 4'd0,  800,  96, 144, 784);
        run_case("10h (EGA 640x350)",              'h10, 0, 8'h00, 4'd0,  800,  96, 144, 784);
        run_case("0Dh (EGA 320x200)",              'h0D, 0, 8'h00, 4'd0,  800, 112, 144, 784);
        run_case("0Dh, overscan colour set",       'h0D, 0, 8'h3F, 4'd0,  800, 112, 144, 784);
        run_case("0Dh, pel panning 1",             'h0D, 0, 8'h00, 4'd1,  800, 112, 144, 784);
        run_case("0Dh, pel panning 7",             'h0D, 0, 8'h00, 4'd7,  800, 112, 144, 784);
        run_case("04h (CGA 320x200)",              'h04, 0, 8'h00, 4'd0,  800, 112, 144, 784);
        run_case("03h (text, 80 columns)",         'h03, 0, 8'h00, 4'd0,  900, 108, 162, 882);
        run_case("01h (text, 40 columns)",         'h01, 0, 8'h00, 4'd0,  900, 126, 162, 882);
        run_case("13h, border shown",              'h13, 1, 8'h3F, 4'd0,  800,  96, 136, 792);
        run_case("0Dh, border shown",              'h0D, 1, 8'h3F, 4'd0,  800, 112, 128, 800);
        run_case("112h (24 bit, tripled dots)",    'h112, 0, 8'h00, 4'd0, 2384, 256, 417, 2337);
        if (errors != 0) $fatal(1, "FAILED: %0d lines off", errors);
        $display("PASS"); $finish;
    end
    initial begin #2_000_000_000; $display("TIMEOUT"); $fatal(1, "timeout"); end
endmodule
