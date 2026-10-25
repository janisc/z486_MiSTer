`timescale 1ns/1ps

// Discworld II streams CPU accesses while SB16 needs two words every 45 us.
// DMA must get the next transaction, without interrupting an accepted burst.
module tb_sdram_dma_priority;
    logic clk = 0;
    always #10 clk = ~clk;
    logic resetn = 0;
    wire busy;
    logic valid0 = 0, valid1 = 0;
    wire ready0, ready1, resp0, resp1, done0;
    logic wr0 = 1;
    logic [3:0] burst0 = 1;
    wire [15:0] dq;
    integer cpu_accepts = 0;
    integer dma_accepts = 0;
    integer dma_responses = 0;
    integer cpu_beats = 0;

    sdram #(.FREQ(50_000_000), .HAS_DQM(1'b0), .FAST_GRADE(1'b1)) dut (
        .clk(clk), .resetn(resetn), .nce(1'b0), .refresh_allowed(1'b1),
        .busy(busy), .sdram_size(2'd1),
        .valid0(valid0), .ready0(ready0), .wr0(wr0),
        .addr0(27'h1000), .din0(32'h12345678), .dout0(), .be0(4'hf),
        .resp_valid0(resp0), .burst_cnt0(burst0), .burst_wrap0(1'b0),
        .burst_done0(done0),
        .valid1(valid1), .ready1(ready1), .wr1(1'b0),
        .addr1(27'h2000), .din1(32'd0), .dout1(), .be1(4'hf),
        .resp_valid1(resp1), .burst_cnt1(4'd1), .burst_wrap1(1'b0),
        .burst_done1(),
        .valid2(1'b0), .ready2(), .wr2(1'b0),
        .addr2(27'd0), .din2(32'd0), .dout2(), .be2(4'd0),
        .resp_valid2(), .burst_cnt2(4'd0), .burst_wrap2(1'b0),
        .burst_done2(),
        .SDRAM_DQ(dq), .SDRAM_A(), .SDRAM_DQM(), .SDRAM_BA(),
        .SDRAM_nWE(), .SDRAM_nRAS(), .SDRAM_nCAS(), .SDRAM_nCS(), .SDRAM_CKE()
    );

    always @(posedge clk) begin
        if (ready0) cpu_accepts++;
        if (ready1) dma_accepts++;
        if (resp1) dma_responses++;
        if (resp0) cpu_beats++;
        if (ready0 && ready1) $fatal(1, "two clients accepted by one SDRAM port");
    end

    task automatic dma_read;
        bit accepted;
        integer old_responses;
        begin
            @(negedge clk);
            old_responses = dma_responses;
            valid1 = 1;
            accepted = 0;
            for (integer n = 0; n < 128; n++) begin
                @(negedge clk);
                if (ready1) begin accepted = 1; break; end
            end
            if (!accepted) $fatal(1, "DMA starved by continuous CPU traffic");
            valid1 = 0;
            for (integer n = 0; n < 128 && dma_responses == old_responses; n++)
                @(negedge clk);
            if (dma_responses != old_responses + 1)
                $fatal(1, "DMA response missing or duplicated");
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;
        wait (!busy);
        // A CPU request is always available, as during a REP copy/cache fill.
        @(negedge clk);
        valid0 = 1;
        repeat (100) @(negedge clk);
        for (integer n = 0; n < 32; n++) begin
            dma_read();
            repeat (20) @(negedge clk);
        end
        @(negedge clk);
        valid0 = 0;
        repeat (128) @(negedge clk);
        if (dma_accepts != 32 || dma_responses != 32 || cpu_accepts == 0)
            $fatal(1, "lost/duplicate request, or CPU made no progress");

        // Arbitration is only between complete transactions: a DMA arrival
        // during an accepted 15-dword CPU burst must not split its responses.
        wr0 = 0;
        burst0 = 15;
        cpu_beats = 0;
        valid0 = 1;
        do @(negedge clk); while (!ready0);
        valid0 = 0;
        valid1 = 1;
        do @(negedge clk); while (!ready1);
        if (cpu_beats != 15) $fatal(1, "DMA preempted CPU read burst (%0d beats)", cpu_beats);
        valid1 = 0;
        repeat (128) @(negedge clk);
        if (dma_accepts != 33 || dma_responses != 33 || cpu_beats != 15)
            $fatal(1, "burst/DMA completion mismatch");
        $display("PASS: bounded DMA latency under CPU saturation; CPU burst preserved");
        $finish;
    end
    initial begin
        #2_000_000;
        $fatal(1, "SDRAM DMA test timeout");
    end
endmodule
