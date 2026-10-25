`timescale 1ns/1ps

// Real byte I/O adapter, both FDC drives, DMA and the HPS sector FIFO.
module tb_floppy_io;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg [31:2] cpu_addr = 0;
    reg [3:0] cpu_be = 0;
    reg [31:0] cpu_din = 0;
    wire [31:0] cpu_dout;
    reg cpu_io_rd = 0, cpu_io_wr = 0;
    wire cpu_io_ready;
    wire [15:0] io_address;
    wire io_read, io_write;
    wire [7:0] io_writedata, io_readdata;
    iobus_adapter adapter (
        .clk(clk), .reset_n(reset_n),
        .cpu_addr(cpu_addr), .cpu_be(cpu_be), .cpu_din(cpu_din),
        .cpu_dout(cpu_dout), .cpu_io_rd(cpu_io_rd), .cpu_io_wr(cpu_io_wr),
        .cpu_io_ready(cpu_io_ready), .io_address(io_address),
        .io_read(io_read), .io_write(io_write),
        .io_writedata(io_writedata), .io_readdata(io_readdata),
        .ide_readdata(32'd0), .ide_hold(1'b0),
        .direct_readdata(8'hff), .direct_handled(1'b0)
    );
    wire selected = io_address[15:3] == (16'h3f0 >> 3);
    reg [3:0] mgmt_address = 0;
    reg mgmt_fddn = 0, mgmt_write = 0, mgmt_read = 0;
    reg [15:0] mgmt_writedata = 0;
    wire [15:0] mgmt_readdata;
    wire [1:0] request;
    wire irq, dma_req;
    reg dma_ack = 0, dma_tc = 0;
    reg [7:0] dma_readdata = 0;
    wire [7:0] dma_writedata;
    floppy dut (
        .clk(clk), .rst_n(reset_n), .io_address(io_address[2:0]),
        .io_read(io_read && selected), .io_write(io_write && selected),
        .io_writedata(io_writedata), .io_readdata(io_readdata),
        .dma_req(dma_req), .dma_ack(dma_ack), .dma_tc(dma_tc),
        .dma_readdata(dma_readdata), .dma_writedata(dma_writedata),
        .mgmt_address(mgmt_address), .mgmt_fddn(mgmt_fddn),
        .mgmt_write(mgmt_write), .mgmt_read(mgmt_read),
        .mgmt_writedata(mgmt_writedata), .mgmt_readdata(mgmt_readdata),
        .wp(2'b00), .clock_rate(28'd85000000), .request(request), .irq(irq)
    );
    function automatic [7:0] pattern(input integer n);
        pattern = 8'(n ^ (n >> 8) ^ 8'h5a);
    endfunction
    task automatic write8(input [15:0] port, input [7:0] value);
        @(negedge clk);
        cpu_addr = port[15:2]; cpu_be = 4'b0001 << port[1:0];
        cpu_din = {4{value}}; cpu_io_wr = 1;
        do @(posedge clk); while (!cpu_io_ready);
        @(negedge clk); cpu_io_wr = 0;
        repeat (2) @(posedge clk);
    endtask
    task automatic read8(input [15:0] port, output [7:0] value);
        @(negedge clk);
        cpu_addr = port[15:2]; cpu_be = 4'b0001 << port[1:0]; cpu_io_rd = 1;
        do @(posedge clk); while (!cpu_io_ready);
        value = 8'(cpu_dout >> (port[1:0] * 8));
        @(negedge clk); cpu_io_rd = 0;
        repeat (2) @(posedge clk);
    endtask
    task automatic command_byte(input [7:0] value);
        reg [7:0] status;
        do read8(16'h3f4, status); while (status[7:6] != 2'b10);
        write8(16'h3f5, value);
    endtask
    task automatic media_write(input bit drive, input [3:0] regno, input [15:0] value);
        @(negedge clk);
        mgmt_address = regno; mgmt_fddn = drive;
        mgmt_writedata = value; mgmt_write = 1;
        @(negedge clk); mgmt_write = 0;
    endtask
    task automatic mount(input bit drive);
        media_write(drive, 0, 1); media_write(drive, 1, 0);
        media_write(drive, 2, 80); media_write(drive, 3, 18);
        media_write(drive, 4, 2880); media_write(drive, 5, 2);
    endtask
    integer dma_count = 0;
    integer dma_gap = 0;
    bit dma_to_pc = 0;
    // Delayed DMA acknowledgments and terminal count on the final byte.
    always @(negedge clk) begin
        dma_ack = 0; dma_tc = 0;
        if (reset_n && dma_req) begin
            if (dma_gap != 0) dma_gap--;
            else begin
                if (dma_count >= 1024) $fatal(1, "extra DMA byte");
                if (dma_to_pc && dma_writedata !== pattern(dma_count))
                    $fatal(1, "DMA read byte %0d: %02x != %02x", dma_count,
                           dma_writedata, pattern(dma_count));
                dma_readdata = pattern(dma_count);
                dma_ack = 1; dma_tc = (dma_count == 1023);
                dma_count++; dma_gap = 3 + dma_count % 7;
            end
        end
    end
    bit expected_drive;
    integer hps_sector = 0;
    integer hps_byte;
    bit hps_active = 0;
    // Space out host accesses to model the board's slow management bus.
    initial forever begin
        @(negedge clk);
        if (reset_n && |request && !hps_active) begin
            hps_active = 1;
            repeat (19) @(negedge clk);
            mgmt_address = 0;
            #1;
            if (mgmt_readdata[15] !== expected_drive || mgmt_readdata[14:0] != hps_sector)
                $fatal(1, "wrong HPS sector/drive %04x, drive %0d sector %0d",
                       mgmt_readdata, expected_drive, hps_sector);
            for (hps_byte = 0; hps_byte < 512; hps_byte++) begin
                mgmt_address = 15;
                if (dma_to_pc) begin
                    mgmt_writedata = {8'd0, pattern(hps_sector * 512 + hps_byte)};
                    mgmt_write = 1;
                end else mgmt_read = 1;
                @(negedge clk);
                mgmt_write = 0; mgmt_read = 0;
                if (!dma_to_pc && mgmt_readdata[7:0] !== pattern(hps_sector * 512 + hps_byte))
                    $fatal(1, "HPS write byte %0d/%0d = %02x", hps_sector,
                           hps_byte, mgmt_readdata[7:0]);
                repeat (2) @(negedge clk);
            end
            hps_sector++; hps_active = 0;
            wait (request == 0);
        end
    end
    task automatic transfer(input bit drive, input bit read_disk);
        reg [7:0] value;
        integer k;
        expected_drive = drive; dma_to_pc = read_disk;
        dma_count = 0; hps_sector = 0;
        write8(16'h3f2, drive ? 8'h2d : 8'h1c);
        command_byte(8'h07); command_byte({7'd0, drive});
        wait (irq);
        command_byte(8'h08);
        read8(16'h3f5, value); read8(16'h3f5, value);
        // The command must override the DOR's previous drive selection.
        // Leave both motors on so only the drive-selection dependency varies.
        write8(16'h3f2, 8'h3c | {7'd0, !drive});
        command_byte(read_disk ? 8'h46 : 8'h45);
        command_byte({7'd0, drive});
        command_byte(0); command_byte(0); command_byte(1);
        command_byte(2); command_byte(2); command_byte(8'h1b); command_byte(8'hff);
        wait (irq);
        if (dma_count != 1024 || hps_sector != 2)
            $fatal(1, "incomplete transfer dma=%0d hps=%0d", dma_count, hps_sector);
        for (k = 0; k < 7; k++) begin
            read8(16'h3f5, value);
            if (k == 0 && (value[7:6] != 0 || value[0] != drive))
                $fatal(1, "bad ST0 %02x", value);
            if ((k == 1 || k == 2) && value != 0)
                $fatal(1, "bad ST%0d %02x", k, value);
        end
        read8(16'h3f4, value);
        if (value[7:4] != 4'h8) $fatal(1, "FDC not idle after result: %02x", value);
        $display("PASS: drive %0d %s, 1024 bytes", drive, read_disk ? "read" : "write");
    endtask
    task automatic rejected_write(input bit write_protect);
        reg [7:0] value;
        integer k;
        // Change only B:'s permissions/geometry while DOR still selects A:.
        media_write(1, 1, write_protect ? 1 : 0);
        media_write(1, 3, write_protect ? 18 : 1);
        write8(16'h3f2, 8'h3c);
        command_byte(8'h45); command_byte(1);
        command_byte(0); command_byte(0); command_byte(2);
        command_byte(2); command_byte(2); command_byte(8'h1b); command_byte(8'hff);
        for (k = 0; k < 7; k++) begin
            read8(16'h3f5, value);
            if (k == 0 && value != 8'h41) $fatal(1, "bad rejected-write ST0 %02x", value);
            if (k == 1 && value != (write_protect ? 8'h27 : 8'h04))
                $fatal(1, "wrong drive permission/geometry status %02x", value);
        end
        if (request != 0) $fatal(1, "rejected command requested HPS data");
        $display("PASS: command-drive %s rejection", write_protect ? "write-protect" : "sector-limit");
    endtask
    task automatic rejected_format;
        reg [7:0] value;
        integer k;
        media_write(1, 1, 1);
        media_write(1, 3, 18);
        write8(16'h3f2, 8'h3c); // DOR A:, command B:
        command_byte(8'h4d); command_byte(1); command_byte(2);
        command_byte(18); command_byte(8'h1b); command_byte(8'hf6);
        for (k = 0; k < 7; k++) begin
            read8(16'h3f5, value);
            if (k == 0 && value != 8'h41) $fatal(1, "bad format ST0 %02x", value);
            if (k == 1 && value != 8'h27) $fatal(1, "wrong format write-protect status %02x", value);
        end
        if (request != 0) $fatal(1, "rejected format requested HPS data");
        $display("PASS: format command-drive write-protect rejection");
    endtask
    initial begin
        repeat (5) @(negedge clk);
        reset_n = 1;
        mount(0); mount(1);
        command_byte(8'h03); command_byte(8'hdf); command_byte(8'h02);
        transfer(0, 0); transfer(1, 0);
        transfer(0, 1); transfer(1, 1);
        rejected_write(1); rejected_write(0);
        rejected_format();
        $display("PASS: FDC adapter/command/result/DMA/HPS regression");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "FDC timeout state=%0d dma=%0d hps=%0d irq=%b msr=%02x",
               dut.state, dma_count, hps_sector, irq, io_readdata);
    end
endmodule
