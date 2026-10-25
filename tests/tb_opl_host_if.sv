`timescale 1ns/1ps
module tb_opl_host_if;
    import opl3_pkg::*;
    logic clk_host = 0, clk = 0;
    always #10 clk_host = ~clk_host;
    always #20.345 clk = ~clk;
    logic reset = 1, ic_n = 0;
    logic cs_n = 1, rd_n = 1, wr_n = 1;
    logic [1:0] address = 0;
    logic [7:0] din = 0;
    wire [7:0] dout;
    wire force_timer_overflow;
    opl3_reg_wr_t opl3_reg_wr;
    opl3_reg_wr_t expected[$];
    integer checked = 0;
    host_if dut(.clk, .reset, .clk_host, .ic_n, .cs_n, .rd_n, .wr_n,
        .address, .din, .dout, .opl3_reg_wr, .status(8'h00), .force_timer_overflow);

    always @(posedge clk) begin
        opl3_reg_wr_t want;
        if (!reset && opl3_reg_wr.valid) begin
            if (expected.size() == 0) $fatal(1, "Unexpected OPL register write");
            want = expected.pop_front();
            if (opl3_reg_wr !== want)
                $fatal(1, "OPL write %0d: got bank=%0d reg=%02x data=%02x; expected bank=%0d reg=%02x data=%02x",
                    checked, opl3_reg_wr.bank_num, opl3_reg_wr.address, opl3_reg_wr.data,
                    want.bank_num, want.address, want.data);
            checked++;
        end
    end
    task automatic put(input [1:0] port_num, input [7:0] value);
        @(negedge clk_host);
        address = port_num; din = value; cs_n = 0; wr_n = 0;
        @(negedge clk_host);
        cs_n = 1; wr_n = 1;
        repeat (2) @(negedge clk_host);
    endtask
    task automatic data_write(input [1:0] port_num, input [7:0] value,
        input logic bank_num, input [7:0] reg_num);
        opl3_reg_wr_t want;
        want.valid = 1; want.bank_num = bank_num;
        want.address = reg_num; want.data = value;
        expected.push_back(want);
        put(port_num, value);
    endtask
    task automatic drain;
        repeat (30) @(negedge clk);
        if (expected.size()) $fatal(1, "Missing %0d OPL writes", expected.size());
    endtask
    task automatic reset_chip;
        drain(); reset = 1; ic_n = 0;
        repeat (8) @(negedge clk);
        reset = 0; ic_n = 1;
        repeat (8) @(negedge clk);
    endtask
    task automatic poll_status;
        repeat (70) begin
            @(negedge clk_host);
            address = 0; cs_n = 0; rd_n = 0;
            @(negedge clk_host);
            cs_n = 1; rd_n = 1;
            repeat (2) @(negedge clk_host);
        end
        repeat (12) @(negedge clk);
    endtask
    initial begin
        repeat (8) @(negedge clk);
        reset = 0; ic_n = 1;
        repeat (8) @(negedge clk);
        // Dragonsphere addresses both ports before writing either data port.
        // With NEW=0 the second address still selects bank 0, not bank 1.
        put(0, 8'hb0); put(2, 8'hb0);
        data_write(1, 8'h21, 0, 8'hb0);
        data_write(3, 8'h21, 0, 8'hb0);
        drain();
        // There is ONE shared address latch. Data-port A1 is ignored.
        put(0, 8'ha0); put(2, 8'hb1);
        data_write(1, 8'h22, 0, 8'hb1);
        data_write(3, 8'h23, 0, 8'hb1);
        // 105h is the exception: reachable with NEW=0, via either data port.
        put(2, 8'h05); data_write(1, 8'h01, 1, 8'h05);
        put(2, 8'ha2); data_write(1, 8'h44, 1, 8'ha2);
        put(0, 8'ha3); data_write(3, 8'h55, 0, 8'ha3);
        put(0, 8'ha4); put(2, 8'hb4);
        data_write(1, 8'h66, 1, 8'hb4);
        data_write(3, 8'h77, 1, 8'hb4);
        put(2, 8'h05); data_write(3, 8'h00, 1, 8'h05);
        put(2, 8'ha5); data_write(3, 8'h88, 0, 8'ha5);
        // Register 005h must not change NEW.
        put(0, 8'h05); data_write(1, 8'h01, 0, 8'h05);
        put(2, 8'ha6); data_write(1, 8'h99, 0, 8'ha6);
        put(2, 8'h05); data_write(3, 8'h01, 1, 8'h05);
        reset_chip();
        put(2, 8'ha7); data_write(3, 8'haa, 0, 8'ha7);
        drain();
        // The host-clock detection helper must use identical bank aliasing.
        put(2, 8'h02); data_write(3, 8'hff, 0, 8'h02);
        put(2, 8'h04); data_write(3, 8'h21, 0, 8'h04);
        drain(); poll_status();
        if (!force_timer_overflow) $fatal(1, "Aliased OPL2 timer was not detected");
        reset_chip();
        put(2, 8'h05); data_write(3, 8'h01, 1, 8'h05);
        put(2, 8'h02); data_write(3, 8'hff, 1, 8'h02);
        put(2, 8'h04); data_write(3, 8'h21, 1, 8'h04);
        drain(); poll_status();
        if (force_timer_overflow) $fatal(1, "Bank-1 writes started bank-0 timer");
        $display("PASS: %0d OPL bank/latch writes and timer checks", checked);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "OPL test timed out");
    end
endmodule
