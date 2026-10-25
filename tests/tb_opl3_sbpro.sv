`timescale 1ns/1ps
module tb_opl3_sbpro;
    logic clk_host = 0, clk = 0;
    always #10 clk_host = ~clk_host;
    always #20.345 clk = ~clk;
    logic ic_n = 0, cs_n = 1, rd_n = 1, wr_n = 1;
    logic [1:0] address = 0;
    logic [7:0] din = 0;
    wire [7:0] dout;
    wire sample_valid, irq_n;
    wire signed [15:0] sample_l, sample_r;
    opl3 dut(.clk, .clk_host, .clk_dac(1'b0), .ic_n, .cs_n, .rd_n,
        .wr_n, .address, .din, .dout, .sample_valid, .sample_l, .sample_r,
        .irq_n, .led());

    task automatic put(input [1:0] port_num, input [7:0] value);
        @(negedge clk_host);
        address = port_num; din = value; cs_n = 0; wr_n = 0;
        @(negedge clk_host);
        cs_n = 1; wr_n = 1;
        repeat (4) @(negedge clk_host);
    endtask
    task automatic paired_write(input [7:0] reg_num, input [7:0] value);
        // Exactly the SB Pro ordering used by Dragonsphere's AdLib driver.
        put(0, reg_num); put(2, reg_num);
        put(1, value); put(3, value);
    endtask

    task automatic native_write(input [7:0] reg_num, input [7:0] value);
        put(2, reg_num); put(3, value);
    endtask

    task automatic check_tone(input string description);
        integer peak, amplitude;
        peak = 0;
        repeat (1200) begin
            @(posedge sample_valid);
            @(negedge clk);
            amplitude = $signed(sample_l);
            if (amplitude < 0) amplitude = -amplitude;
            if (amplitude > peak) peak = amplitude;
            if (sample_l !== sample_r) $fatal(1, "%s: left/right differ", description);
        end
        if (peak < 100) $fatal(1, "%s produced silence (peak %0d)", description, peak);
        $display("PASS: %s, peak=%0d", description, peak);
    endtask

    initial begin
        repeat (10) @(negedge clk);
        ic_n = 1;
        repeat (1000) @(negedge clk);
        // OPL2-compatible, two-operator channel 0. Carrier audible, modulator
        // muted; NEW is deliberately never enabled through register 105h.
        paired_write(8'h20, 8'h21); paired_write(8'h23, 8'h21);
        paired_write(8'h40, 8'h3f); paired_write(8'h43, 8'h00);
        paired_write(8'h60, 8'hf0); paired_write(8'h63, 8'hf0);
        paired_write(8'h80, 8'h00); paired_write(8'h83, 8'h00);
        paired_write(8'hc0, 8'h01);
        paired_write(8'ha0, 8'h98); paired_write(8'hb0, 8'h31);
        check_tone("paired SB Pro writes produce OPL3 compatibility audio");

        // Native OPL3 bank 1 must remain usable once NEW has been enabled.
        ic_n = 0;
        repeat (10) @(negedge clk);
        ic_n = 1;
        repeat (1000) @(negedge clk);
        native_write(8'h05, 8'h01);
        native_write(8'h20, 8'h21); native_write(8'h23, 8'h21);
        native_write(8'h40, 8'h3f); native_write(8'h43, 8'h00);
        native_write(8'h60, 8'hf0); native_write(8'h63, 8'hf0);
        native_write(8'h80, 8'h00); native_write(8'h83, 8'h00);
        native_write(8'hc0, 8'h31); // enable both output channels in native mode
        native_write(8'ha0, 8'h98); native_write(8'hb0, 8'h31);
        check_tone("native OPL3 bank-1 audio after NEW=1");
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "OPL3 tone test timed out");
    end
endmodule
