`timescale 1ns/1ps

module tb_sdram_partial;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    always #10 clk = ~clk;

    wire [15:0] sdram_dq;
    wire [12:0] sdram_a;
    wire  [1:0] sdram_dqm;
    wire  [1:0] sdram_ba;
    wire        sdram_nwe;
    wire        sdram_nras;
    wire        sdram_ncas;
    wire        sdram_ncs;
    wire        sdram_cke;

    reg         valid = 1'b0;
    wire        ready;
    reg         wr = 1'b0;
    reg  [24:0] addr = 25'd0;
    reg  [31:0] din = 32'd0;
    wire [31:0] dout;
    reg   [3:0] be = 4'hF;
    wire        resp_valid;
    reg   [3:0] burst_cnt = 4'd1;
    reg         burst_wrap = 1'b0;
    wire        burst_done;
    wire        busy;

    wire ready1, ready2;
    wire [31:0] dout1, dout2;
    wire resp_valid1, resp_valid2;
    wire burst_done1, burst_done2;

    sdram #(
        .FREQ(50_000_000),
        .HAS_DQM(1'b0),
        .FAST_GRADE(1'b1)
    ) dut (
        .SDRAM_DQ         (sdram_dq),
        .SDRAM_A          (sdram_a),
        .SDRAM_DQM        (sdram_dqm),
        .SDRAM_BA         (sdram_ba),
        .SDRAM_nWE        (sdram_nwe),
        .SDRAM_nRAS       (sdram_nras),
        .SDRAM_nCAS       (sdram_ncas),
        .SDRAM_nCS        (sdram_ncs),
        .SDRAM_CKE        (sdram_cke),
        .clk              (clk),
        .resetn           (resetn),
        .nce              (1'b0),
        .refresh_allowed  (1'b0),
        .busy             (busy),
        .valid0           (valid),
        .ready0           (ready),
        .wr0              (wr),
        .addr0            (addr),
        .din0             (din),
        .dout0            (dout),
        .be0              (be),
        .resp_valid0      (resp_valid),
        .burst_cnt0       (burst_cnt), .burst_wrap0(burst_wrap),
        .burst_done0      (burst_done),
        .valid1           (1'b0),
        .ready1           (ready1),
        .wr1              (1'b0),
        .addr1            (25'd0),
        .din1             (32'd0),
        .dout1            (dout1),
        .be1              (4'd0),
        .resp_valid1      (resp_valid1),
        .burst_cnt1       (4'd0), .burst_wrap1(1'b0),
        .burst_done1      (burst_done1),
        .valid2           (1'b0),
        .ready2           (ready2),
        .wr2              (1'b0),
        .addr2            (25'd0),
        .din2             (32'd0),
        .dout2            (dout2),
        .be2              (4'd0),
        .resp_valid2      (resp_valid2),
        .burst_cnt2       (4'd0), .burst_wrap2(1'b0),
        .burst_done2      (burst_done2)
    );

    localparam CMD_SetModeReg   = 3'b000;
    localparam CMD_AutoRefresh  = 3'b001;
    localparam CMD_PreCharge    = 3'b010;
    localparam CMD_BankActivate = 3'b011;
    localparam CMD_Write        = 3'b100;
    localparam CMD_Read         = 3'b101;

    reg [15:0] sdram_mem [int unsigned];
    reg [12:0] active_row [0:3];
    reg        active_valid [0:3];
    reg        dq_drive_en = 1'b0;
    reg [15:0] dq_drive = 16'd0;
    assign sdram_dq = dq_drive_en ? dq_drive : 16'hzzzz;

    reg        rd_valid_pipe [0:2];
    reg [15:0] rd_data_pipe [0:2];
    integer read_cmd_count = 0;
    integer write_cmd_count = 0;

    function automatic int unsigned half_index(input [1:0] bank, input [12:0] row, input [8:0] col);
    begin
        half_index = {bank, row, col};
    end
    endfunction

    function automatic int unsigned half_index_from_addr(input [24:0] byte_addr, input bit hi);
    begin
        half_index_from_addr = {byte_addr[24:23], byte_addr[22:10], byte_addr[9:2], hi};
    end
    endfunction

    task automatic poke_word(input [24:0] byte_addr, input [31:0] value);
    begin
        sdram_mem[half_index_from_addr(byte_addr, 1'b0)] = value[15:0];
        sdram_mem[half_index_from_addr(byte_addr, 1'b1)] = value[31:16];
    end
    endtask

    task automatic check_eq32(input [31:0] got, input [31:0] exp, input string msg);
    begin
        if (got !== exp) begin
            $display("FAIL: %s got=%08x exp=%08x", msg, got, exp);
            $fatal(1);
        end
    end
    endtask

    task automatic check_eq_int(input integer got, input integer exp, input string msg);
    begin
        if (got != exp) begin
            $display("FAIL: %s got=%0d exp=%0d", msg, got, exp);
            $fatal(1);
        end
    end
    endtask

    always @(negedge clk) begin
        automatic reg [2:0] cmd;
        automatic reg [8:0] col;
        automatic int unsigned idx;
        cmd = {sdram_nras, sdram_ncas, sdram_nwe};

        rd_valid_pipe[0] = rd_valid_pipe[1];
        rd_data_pipe[0]  = rd_data_pipe[1];
        rd_valid_pipe[1] = rd_valid_pipe[2];
        rd_data_pipe[1]  = rd_data_pipe[2];
        rd_valid_pipe[2] = 1'b0;
        rd_data_pipe[2]  = 16'd0;

        if (!sdram_ncs) begin
            case (cmd)
            CMD_BankActivate: begin
                active_row[sdram_ba] = sdram_a;
                active_valid[sdram_ba] = 1'b1;
            end
            CMD_Read: begin
                col = sdram_a[8:0];
                idx = half_index(sdram_ba, active_row[sdram_ba], col);
                rd_valid_pipe[2] = active_valid[sdram_ba];
                rd_data_pipe[2]  = sdram_mem.exists(idx) ? sdram_mem[idx] : 16'h0000;
                read_cmd_count++;
            end
            CMD_Write: begin
                col = sdram_a[8:0];
                idx = half_index(sdram_ba, active_row[sdram_ba], col);
                if (active_valid[sdram_ba]) sdram_mem[idx] = sdram_dq;
                write_cmd_count++;
            end
            CMD_PreCharge: begin
                if (sdram_a[10]) begin
                    active_valid[0] = 1'b0;
                    active_valid[1] = 1'b0;
                    active_valid[2] = 1'b0;
                    active_valid[3] = 1'b0;
                end else begin
                    active_valid[sdram_ba] = 1'b0;
                end
            end
            CMD_AutoRefresh, CMD_SetModeReg: begin
            end
            default: begin
            end
            endcase
        end

        dq_drive_en = rd_valid_pipe[0];
        dq_drive    = rd_data_pipe[0];
    end

    task automatic wait_controller_idle;
        integer i;
    begin
        for (i = 0; i < 30000; i = i + 1) begin
            if (!busy) return;
            @(posedge clk);
        end
        $display("FAIL: timeout waiting for controller idle");
        $fatal(1);
    end
    endtask

    task automatic host_write(input [24:0] a, input [31:0] data, input [3:0] mask);
        integer i;
    begin
        addr = a;
        din = data;
        be = mask;
        wr = 1'b1;
        burst_cnt = 4'd1;
        valid = 1'b1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (ready) begin
                valid = 1'b0;
                wr = 1'b0;
                wait_controller_idle();
                return;
            end
        end
        $display("FAIL: write not accepted");
        $fatal(1);
    end
    endtask

    task automatic host_read(input [24:0] a, output [31:0] data);
        integer i;
    begin
        addr = a;
        din = 32'd0;
        be = 4'hF;
        wr = 1'b0;
        burst_cnt = 4'd1;
        valid = 1'b1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (ready) begin
                valid = 1'b0;
                break;
            end
        end
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (resp_valid) begin
                data = dout;
                wait_controller_idle();
                return;
            end
        end
        $display("FAIL: read data not returned");
        $fatal(1);
    end
    endtask

    // A 4-dword read: wrapping (a cache line from its requested dword) or linear.
    task automatic check_burst_case(input string name, input [24:0] a, input bit wrap,
                                    input [31:0] e0, input [31:0] e1,
                                    input [31:0] e2, input [31:0] e3);
        integer i, n;
        reg [31:0] got [0:3];
    begin
        addr = a;
        be = 4'hF;
        wr = 1'b0;
        burst_cnt = 4'd4;
        burst_wrap = wrap;
        valid = 1'b1;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (ready) begin
                valid = 1'b0;
                break;
            end
        end
        n = 0;
        for (i = 0; i < 400 && n < 4; i = i + 1) begin
            @(posedge clk);
            if (resp_valid) begin
                got[n] = dout;
                n = n + 1;
            end
        end
        check_eq_int(n, 4, {name, " beat count"});
        check_eq32(got[0], e0, {name, " beat 0"});
        check_eq32(got[1], e1, {name, " beat 1"});
        check_eq32(got[2], e2, {name, " beat 2"});
        check_eq32(got[3], e3, {name, " beat 3"});
        burst_cnt = 4'd1;
        burst_wrap = 1'b0;
        wait_controller_idle();
    end
    endtask

    task automatic check_write_case(
        input string name,
        input [24:0] a,
        input [31:0] initial_value,
        input [31:0] write_value,
        input [3:0] mask,
        input [31:0] expected,
        input integer exp_reads,
        input integer exp_writes
    );
        reg [31:0] got;
    begin
        poke_word(a, initial_value);
        read_cmd_count = 0;
        write_cmd_count = 0;
        host_write(a, write_value, mask);
        check_eq_int(read_cmd_count, exp_reads, {name, " read command count"});
        check_eq_int(write_cmd_count, exp_writes, {name, " write command count"});
        host_read(a, got);
        check_eq32(got, expected, name);
    end
    endtask

    initial begin
        rd_valid_pipe[0] = 1'b0;
        rd_valid_pipe[1] = 1'b0;
        rd_valid_pipe[2] = 1'b0;
        active_valid[0] = 1'b0;
        active_valid[1] = 1'b0;
        active_valid[2] = 1'b0;
        active_valid[3] = 1'b0;

        repeat (4) @(posedge clk);
        resetn = 1'b1;
        wait_controller_idle();

        check_write_case("low half direct",  25'h00100, 32'h11223344, 32'h0000BEEF, 4'b0011, 32'h1122BEEF, 0, 1);
        check_write_case("high half direct", 25'h00104, 32'h11223344, 32'hCAFE0000, 4'b1100, 32'hCAFE3344, 0, 1);
        check_write_case("low byte rmw",     25'h00108, 32'h11223344, 32'h000000AA, 4'b0001, 32'h112233AA, 1, 1);
        check_write_case("high byte rmw",    25'h0010C, 32'h11223344, 32'h00BB0000, 4'b0100, 32'h11BB3344, 1, 1);
        check_write_case("cross half rmw",   25'h00110, 32'h11223344, 32'h00CCDD00, 4'b0110, 32'h11CCDD44, 2, 2);
        check_write_case("full dword",       25'h00114, 32'h11223344, 32'hAABBCCDD, 4'b1111, 32'hAABBCCDD, 0, 2);

        // Line reads: critical dword first, wrapping within the 16-byte line.
        poke_word(25'h00200, 32'hA0A0A0A0);
        poke_word(25'h00204, 32'hA1A1A1A1);
        poke_word(25'h00208, 32'hA2A2A2A2);
        poke_word(25'h0020C, 32'hA3A3A3A3);
        poke_word(25'h00210, 32'hB0B0B0B0);
        poke_word(25'h00214, 32'hB1B1B1B1);
        check_burst_case("wrap from dword 2", 25'h00208, 1'b1,
                         32'hA2A2A2A2, 32'hA3A3A3A3, 32'hA0A0A0A0, 32'hA1A1A1A1);
        check_burst_case("wrap from dword 0", 25'h00200, 1'b1,
                         32'hA0A0A0A0, 32'hA1A1A1A1, 32'hA2A2A2A2, 32'hA3A3A3A3);
        check_burst_case("wrap from dword 3", 25'h0020C, 1'b1,
                         32'hA3A3A3A3, 32'hA0A0A0A0, 32'hA1A1A1A1, 32'hA2A2A2A2);
        check_burst_case("linear from dword 2", 25'h00208, 1'b0,
                         32'hA2A2A2A2, 32'hA3A3A3A3, 32'hB0B0B0B0, 32'hB1B1B1B1);

        $display("PASS: tb_sdram_partial completed");
        $finish;
    end
endmodule
