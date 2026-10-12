`timescale 1ns / 1ns

module tb_rtc_ram_size;
    logic clk = 0;
    logic rst_n = 0;
    logic [1:0] ram_size = 0;
    logic io_address = 0;
    logic io_read = 0;
    logic io_write = 0;
    logic [7:0] io_writedata = 0;
    logic [7:0] io_readdata;
    logic [7:0] io_readdata_no_fpu;
    logic [7:0] io_readdata_fpu_off;
    logic [7:0] mgmt_address = 0;
    logic mgmt_write = 0;
    logic [7:0] mgmt_writedata = 0;
    logic irq;
    integer rtc_ticks;

    always #5 clk = ~clk;

    rtc #(
        .FPU_PRESENT(1'b1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .irq(irq),
        .io_address(io_address),
        .io_read(io_read),
        .io_readdata(io_readdata),
        .io_write(io_write),
        .io_writedata(io_writedata),
        .bootcfg(6'd0),
        .ram_size(ram_size),
        .fpu_off(1'b0),
        .mgmt_address(mgmt_address),
        .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata),
        .clock_rate(28'd85_000_000)
    );

    rtc dut_no_fpu (
        .clk(clk),
        .rst_n(rst_n),
        .irq(),
        .io_address(io_address),
        .io_read(io_read),
        .io_readdata(io_readdata_no_fpu),
        .io_write(io_write),
        .io_writedata(io_writedata),
        .bootcfg(6'd0),
        .ram_size(ram_size),
        .fpu_off(1'b0),
        .mgmt_address(mgmt_address),
        .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata),
        .clock_rate(28'd85_000_000)
    );

    // An FPU build with the x87 switched off reads back as a build without one.
    rtc #(
        .FPU_PRESENT(1'b1)
    ) dut_fpu_off (
        .clk(clk),
        .rst_n(rst_n),
        .irq(),
        .io_address(io_address),
        .io_read(io_read),
        .io_readdata(io_readdata_fpu_off),
        .io_write(io_write),
        .io_writedata(io_writedata),
        .bootcfg(6'd0),
        .ram_size(ram_size),
        .fpu_off(1'b1),
        .mgmt_address(mgmt_address),
        .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata),
        .clock_rate(28'd85_000_000)
    );

    task automatic select_cmos(input logic [6:0] address);
        begin
            @(negedge clk);
            io_address = 0;
            io_writedata = {1'b0, address};
            io_write = 1;
            @(negedge clk);
            io_write = 0;
        end
    endtask

    task automatic write_mgmt_cmos(input logic [7:0] address, input logic [7:0] data);
        begin
            @(negedge clk);
            mgmt_address = address;
            mgmt_writedata = data;
            mgmt_write = 1;
            @(negedge clk);
            mgmt_write = 0;
        end
    endtask

    task automatic expect_cmos_no_fpu(input logic [6:0] address, input logic [7:0] expected);
        begin
            select_cmos(address);
            @(negedge clk);
            io_address = 1;
            io_read = 1;
            @(negedge clk);
            io_read = 0;
            if (io_readdata_no_fpu !== expected) begin
                $error("no-FPU CMOS %02h: expected %02h, got %02h",
                       address, expected, io_readdata_no_fpu);
                $fatal;
            end
            if (io_readdata_fpu_off !== expected) begin
                $error("x87-off CMOS %02h: expected %02h, got %02h",
                       address, expected, io_readdata_fpu_off);
                $fatal;
            end
        end
    endtask

    task automatic expect_cmos(input logic [6:0] address, input logic [7:0] expected);
        begin
            select_cmos(address);
            @(negedge clk);
            io_address = 1;
            io_read = 1;
            @(negedge clk);
            io_read = 0;
            if (io_readdata !== expected) begin
                $error("CMOS %02h: expected %02h, got %02h", address, expected, io_readdata);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;

        expect_cmos(7'h17, 8'h00);
        expect_cmos(7'h18, 8'h3C);
        expect_cmos(7'h30, 8'h00);
        expect_cmos(7'h31, 8'h3C);
        expect_cmos(7'h34, 8'h00);
        expect_cmos(7'h35, 8'h00);
        expect_cmos(7'h14, 8'h06);
        expect_cmos(7'h2E, 8'h00);
        expect_cmos(7'h2F, 8'h06);
        expect_cmos_no_fpu(7'h14, 8'h04);
        expect_cmos_no_fpu(7'h2F, 8'h04);

        ram_size = 1;
        expect_cmos(7'h17, 8'h00);
        expect_cmos(7'h18, 8'h7C);
        expect_cmos(7'h30, 8'h00);
        expect_cmos(7'h31, 8'h7C);
        expect_cmos(7'h34, 8'h00);
        expect_cmos(7'h35, 8'h01);
        expect_cmos(7'h2E, 8'h00);
        expect_cmos(7'h2F, 8'h46);

        ram_size = 2;
        expect_cmos(7'h17, 8'h00);
        expect_cmos(7'h18, 8'hFC);
        expect_cmos(7'h30, 8'h00);
        expect_cmos(7'h31, 8'hFC);
        expect_cmos(7'h34, 8'h00);
        expect_cmos(7'h35, 8'h03);
        expect_cmos(7'h2E, 8'h00);
        expect_cmos(7'h2F, 8'hC6);

        ram_size = 3;
        expect_cmos(7'h17, 8'hFF);
        expect_cmos(7'h18, 8'hFF);
        expect_cmos(7'h30, 8'hFF);
        expect_cmos(7'h31, 8'hFF);
        expect_cmos(7'h34, 8'h00);
        expect_cmos(7'h35, 8'h07);
        expect_cmos(7'h2E, 8'h01);
        expect_cmos(7'h2F, 8'hC8);

        // Preserve Main's equipment byte and adjust its checksum only for
        // synthesized equipment bits that are not already present.
        ram_size = 0;
        write_mgmt_cmos(8'h14, 8'h4D);
        write_mgmt_cmos(8'h2E, 8'h12);
        write_mgmt_cmos(8'h2F, 8'h34);
        expect_cmos(7'h14, 8'h4F);
        expect_cmos(7'h2E, 8'h12);
        expect_cmos(7'h2F, 8'h36);
        expect_cmos_no_fpu(7'h14, 8'h4D);
        expect_cmos_no_fpu(7'h2E, 8'h12);
        expect_cmos_no_fpu(7'h2F, 8'h34);

        // Ten milliseconds at 85 MHz must produce about 82 RTC base ticks.
        rtc_ticks = 0;
        repeat (850_000) begin
            @(negedge clk);
            if (dut.ce_8192hz)
                rtc_ticks = rtc_ticks + 1;
        end
        if (rtc_ticks < 81 || rtc_ticks > 83) begin
            $error("RTC base clock: expected 81-83 ticks, got %0d", rtc_ticks);
            $fatal;
        end

        $display("PASS: RTC memory sizes and 8192 Hz base clock (%0d ticks)", rtc_ticks);
        $finish;
    end
endmodule
