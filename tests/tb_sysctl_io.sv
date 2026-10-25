`timescale 1ns/1ps

module tb_sysctl_io;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [31:2] cpu_addr = 0;
    logic [3:0] cpu_be = 0;
    logic [31:0] cpu_din = 0;
    wire [31:0] cpu_dout;
    logic cpu_io_rd = 0, cpu_io_wr = 0;
    wire cpu_io_ready;
    wire [15:0] io_address, io_address_next;
    wire io_address_load, io_read, io_write;
    wire [7:0] io_writedata, sysctl_data;
    logic io_cs = 0;
    logic [2:0] osd_speed = 0;
    wire [2:0] speed_sel;
    wire [7:0] control;
    wire [7:0] io_readdata = io_cs ? sysctl_data : 8'hff;
    always @(posedge clk)
        if (io_address_load) io_cs <= (io_address_next[15:3] == (16'h8888 >> 3));

    iobus_adapter adapter (
        .clk, .reset_n, .cpu_addr, .cpu_be, .cpu_din, .cpu_dout,
        .cpu_io_rd, .cpu_io_wr, .cpu_io_ready,
        .io_address, .io_address_next, .io_address_load, .io_read, .io_write,
        .io_writedata, .io_readdata,
        .ide_address(), .ide_read(), .ide_write(), .ide_writedata(),
        .ide_readdata(32'd0), .ide_32(), .ide_hold(1'b0),
        .direct_readdata(8'hff), .direct_handled(1'b0)
    );
    sysctl dut (
        .clk, .reset(!reset_n), .io_address(io_address[2:0]), .io_write,
        .io_cs, .io_writedata, .io_readdata(sysctl_data),
        .osd_speed, .speed_sel, .control
    );

    task automatic transfer(input logic wr, input logic [15:0] port_num,
                            input integer bytes_n, input logic [31:0] data,
                            output logic [31:0] received);
        integer timeout_n;
        @(negedge clk);
        cpu_addr = {16'd0, port_num[15:2]};
        cpu_be = 4'(((1 << bytes_n) - 1) << port_num[1:0]);
        cpu_din = data << (8 * port_num[1:0]);
        cpu_io_wr = wr;
        cpu_io_rd = !wr;
        timeout_n = 0;
        do begin
            @(posedge clk);
            #1;
            timeout_n++;
            if (timeout_n > 100) $fatal(1, "SYSCTL I/O timeout");
        end while (!cpu_io_ready);
        received = cpu_dout >> (8 * port_num[1:0]);
        @(negedge clk);
        cpu_io_rd = 0;
        cpu_io_wr = 0;
        repeat (3) @(negedge clk);
    endtask

    initial begin
        logic [31:0] got;
        integer selected;
        repeat (3) @(negedge clk);
        reset_n = 1;
        // Exact original OSD bit patterns, including saved four-speed CFGs.
        for (integer s = 0; s < 8; s++) begin
            osd_speed = 3'(s);
            #1;
            selected = s < 4 ? ((s >> 1) ^ (s & 1)) * 2 + (s & 1) : s;
            if (speed_sel != selected) $fatal(1, "OSD selector %0d mapped to %0d", s, speed_sel);
        end
        transfer(0, 16'h888a, 2, 0, got);
        if (got[15:0] != 16'h345a) $fatal(1, "missing Z4 signature");
        transfer(0, 16'h888c, 4, 0, got);
        if (got != 32'hff013638) $fatal(1, "bad 86/revision/mask: %08x", got);
        for (integer s = 0; s < 8; s++) begin
            transfer(1, 16'h8888, 2, 32'ha180 | s, got);
            if ((speed_sel != s) || (control != (8'h80 | 8'(s))))
                $fatal(1, "SYSCTL selector %0d failed", s);
            osd_speed = 3'(7 - s);
            #1;
            if (speed_sel != s) $fatal(1, "OSD overrode SYSCTL ownership");
        end
        // Cache bits retain their meanings/reserved storage; they are not speeds.
        transfer(1, 16'h8888, 2, 32'ha1b3, got);
        if ((control != 8'hb3) || (speed_sel != 3)) $fatal(1, "legacy cache bits changed speed");
        transfer(1, 16'h8888, 2, 32'h0080, got);
        if (control != 8'hb3) $fatal(1, "invalid commit signature was accepted");
        transfer(1, 16'h888a, 2, 32'ha180, got);
        if (control != 8'hb3) $fatal(1, "capability write changed configuration");
        transfer(1, 16'h8888, 2, 32'ha100, got);
        osd_speed = 3'd4;
        #1;
        if ((control != 0) || (speed_sel != 4)) $fatal(1, "SYSCTL MENU did not restore OSD");
        transfer(0, 16'h8888, 2, 0, got);
        if (got[15:0] != 16'ha100) $fatal(1, "control readback failed");
        $display("SYSCTL PASS: eight OSD/rate encodings, legacy OUTW, capability ABI, ownership");
        $finish;
    end
endmodule
