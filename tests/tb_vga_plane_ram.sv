`timescale 1ns/1ps

module tb_vga_plane_ram;
    logic clk = 0;
    logic [15:0] host_address = 0;
    logic [7:0] host_writedata = 0;
    logic host_write = 0;
    wire [7:0] host_readdata;
    logic [15:0] video_address = 0;
    logic video_enable = 0;
    wire [7:0] video_readdata;

    always #5 clk = ~clk;

    vga_plane_ram #(.USE_URAM(1'b1)) dut (
        .clk_sys(clk),
        .clk_vga(clk),
        .host_address(host_address),
        .host_writedata(host_writedata),
        .host_write(host_write),
        .host_readdata(host_readdata),
        .video_address(video_address),
        .video_enable(video_enable),
        .video_readdata(video_readdata)
    );

    task automatic write_host(input [15:0] address, input [7:0] data);
        host_address = address;
        host_writedata = data;
        host_write = 1'b1;
        @(posedge clk);
        #1;
        host_write = 1'b0;
    endtask

    task automatic read_video(input [15:0] address, input [7:0] expected);
        video_address = address;
        video_enable = 1'b1;
        @(posedge clk);
        #1;
        if (video_readdata !== expected)
            $fatal(1, "video read %04x returned %02x, expected %02x",
                   address, video_readdata, expected);
    endtask

    task automatic read_host(input [15:0] address, input [7:0] expected);
        host_address = address;
        @(posedge clk);
        #1;
        if (host_readdata !== expected)
            $fatal(1, "host read %04x returned %02x, expected %02x",
                   address, host_readdata, expected);
    endtask

    initial begin
        integer i;

        // Exercise every byte lane within one packed 64-bit URAM word.
        for (i = 0; i < 8; i = i + 1)
            write_host(16'h0120 + i[15:0], 8'ha0 + i[7:0]);
        write_host(16'h8123, 8'h5a);

        for (i = 0; i < 8; i = i + 1) begin
            read_host(16'h0120 + i[15:0], 8'ha0 + i[7:0]);
            read_video(16'h0120 + i[15:0], 8'ha0 + i[7:0]);
        end
        read_video(16'h8123, 8'h5a);

        video_enable = 1'b0;
        video_address = 16'h0123;
        @(posedge clk);
        #1;
        if (video_readdata !== 8'h5a)
            $fatal(1, "disabled video port did not hold its output");

        $display("PASS: common-clock VGA plane RAM host/video access");
        $finish;
    end
endmodule
