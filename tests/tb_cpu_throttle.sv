`timescale 1ns/1ps

module throttle_check #(parameter integer MHZ = 85)(output logic done = 0);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [2:0] speed_sel = 0;
    logic active_cycle = 0;
    wire hold, release_cycle, full_speed;
    cpu_throttle #(.CLOCK_RATE_MHZ(MHZ)) dut (.*);

    function automatic integer target(input integer s);
        case (s)
            0: target = MHZ;
            1: target = 15;
            2: target = 30;
            3: target = (MHZ < 56) ? MHZ : 56;
            4: target = 6;
            5: target = 5;
            6: target = 4;
            default: target = 3;
        endcase
    endfunction

    task automatic tick(input logic run_cycle);
        @(negedge clk);
        active_cycle = run_cycle;
        @(posedge clk);
        #1;
        if (release_cycle && !hold)
            $fatal(1, "%0d MHz: release without hold", MHZ);
    endtask

    initial begin
        integer runs, expected;
        tick(0);
        reset_n = 1;
        for (integer s = 0; s < 8; s++) begin
            speed_sel = 3'(s);
            tick(0);
            tick(0);
            runs = 0;
            for (integer n = 0; n < MHZ * 200; n++) begin
                if (!hold) runs++;
                tick(!hold);
            end
            expected = target(s) * 200;
            if ((runs < expected - 2) || (runs > expected + 2))
                $fatal(1, "%0d MHz selector %0d: ran %0d, expected %0d", MHZ, s, runs, expected);
        end
        // Every live transition, including while debt is outstanding. Idle
        // clocks model cache/peripheral stalls; they must not strand hold.
        for (integer old_s = 0; old_s < 8; old_s++) begin
            for (integer new_s = 0; new_s < 8; new_s++) begin
                speed_sel = 3'(old_s);
                tick(0);
                for (integer n = 0; n < 120; n++) tick(!hold);
                speed_sel = 3'(new_s);
                tick(0);
                if ((old_s != new_s) && (hold || release_cycle))
                    $fatal(1, "%0d MHz transition %0d -> %0d did not reset debt", MHZ, old_s, new_s);
                for (integer n = 0; n < 120; n++) tick(!hold && (n % 3 != 0));
                repeat (MHZ + 2) tick(0);
                if (hold)
                    $fatal(1, "%0d MHz selector %0d stuck after idle", MHZ, new_s);
            end
        end
        reset_n = 0;
        tick(0);
        if (hold || release_cycle || !full_speed) $fatal(1, "reset failed");
        $display("throttle PASS at %0d MHz: eight rates and 64 live transitions", MHZ);
        done = 1;
    end
endmodule

module tb_cpu_throttle;
    wire a, b, c;
    throttle_check #(.MHZ(50)) base_check(a);
    throttle_check #(.MHZ(65)) debug_check(b);
    throttle_check #(.MHZ(85)) production_check(c);
    initial begin
        wait (a && b && c);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "throttle timeout");
    end
endmodule
