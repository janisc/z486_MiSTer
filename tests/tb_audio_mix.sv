`timescale 1ns/1ps
// The last two stages of the audio mix in z486_mister.sv: mix_dc_block (takes a constant offset out) and acompr
// (Audio Boost).
//
// A Sound Blaster DSP holds its last value for ever. Monkey Island leaves it at full scale, which is -4 dB or 20676
// in the mix: measured on the analog output, Audio Boost then made the music 12 dB (2x) and about 20 dB (4x)
// quieter, and the mix clipped 8.7 dB early with the boost off. And acompr wrapped at the top of its range:
// 41 input values at 4x and 5 at 2x came out with the opposite sign.
//
// Run it from this folder (both modules are cut out of the top file):
//   $ sed -n '/^module mix_dc_block/,/^endmodule/p;/^module acompr/,/^endmodule/p' ../z486_mister.sv > audio_mods.sv
//   $ iverilog -g2012 -o tb_audio_mix tb_audio_mix.sv audio_mods.sv && vvp tb_audio_mix
// or with Verilator:
//   $ verilator --binary --timing -Wno-fatal --Mdir obj_dir/audio_mix --top-module tb_audio_mix \
//       tb_audio_mix.sv audio_mods.sv -o ../Vtb_audio_mix && ./obj_dir/Vtb_audio_mix
module tb_audio_mix;
    logic clk = 0;
    always #5 clk = ~clk;
    int errors = 0;

    // ---- DC block: one simulated clock per 48 kHz sample (ce always on)
    logic signed [18:0] mix = 0;
    wire  signed [15:0] ac;
    mix_dc_block dcb(.clk(clk), .ce(1'b1), .inp(mix), .out(ac));

    real pi = 3.14159265358979;
    real sum, sq, peak;

    // plays a sine of the given frequency and amplitude on a given offset and measures the last `n` samples
    task play(input real freq, input real amp, input int dc, input int settle, input int n);
        sum = 0; sq = 0; peak = 0;
        for (int i = 0; i < settle + n; i++) begin
            mix = dc + $rtoi(amp * $sin(2 * pi * freq * i / 48000.0));
            @(posedge clk); #1;
            if (i >= settle) begin
                sum = sum + ac; sq = sq + 1.0 * ac * ac;
                if (ac > peak) peak = ac;
                if (-ac > peak) peak = -ac;
            end
        end
        sum = sum / n;
        sq = $sqrt(sq / n);
    endtask

    task check(input string what, input real got, input real lo, input real hi);
        if (got < lo || got > hi) begin errors++; $display("FAIL %s: %0.2f, expected %0.2f..%0.2f", what, got, lo, hi); end
        else $display("ok   %s: %0.2f", what, got);
    endtask

    // ---- Audio Boost
    logic mode = 0;
    logic signed [15:0] inp = 0;
    wire  signed [15:0] out;
    acompr boost(.clk(clk), .mode(mode), .inp(inp), .out(out));

    int prev, wrong, down;
    initial begin
        // music with no offset passes unchanged
        play(440, 1500, 0, 4800, 48000);
        check("440 Hz, no offset: RMS", sq, 1500 / 1.41421 * 0.995, 1500 / 1.41421 * 1.005);
        check("440 Hz, no offset: mean", sum, -2, 2);
        // the offset of a Sound Blaster stuck at full scale, both ways
        play(440, 1500, -20676, 48000, 48000);
        check("440 Hz on -20676: RMS", sq, 1500 / 1.41421 * 0.995, 1500 / 1.41421 * 1.005);
        check("440 Hz on -20676: mean", sum, -2, 2);
        play(440, 12000, 20676, 48000, 48000);
        check("440 Hz, loud, on 20676: peak (clipped at 12091 above the offset before)", peak, 11900, 12100);
        // bass and the corner frequency
        play(40, 1500, 0, 96000, 48000);
        check("40 Hz: RMS", sq, 1500 / 1.41421 * 0.985, 1500 / 1.41421 * 1.005);
        play(3.73, 1500, 0, 96000, 96514);
        check("3.73 Hz: RMS (-3 dB)", sq, 1500 / 1.41421 * 0.68, 1500 / 1.41421 * 0.74);
        // the sum saturates, it does not wrap
        play(440, 120000, 0, 4800, 48000);
        check("sum of 120000: peak", peak, 32767, 32768);

        // every input of the boost: same sign, never falling
        for (int m = 0; m < 2; m++) begin
            mode = m; prev = -40000; wrong = 0; down = 0;
            for (int v = -32768; v <= 32767; v++) begin
                inp = v;
                repeat (5) @(posedge clk);
                #1;
                if ((v > 0 && out < 0) || (v < 0 && out > 0)) wrong++;
                if (out < prev) down++;
                prev = out;
            end
            check(m ? "Audio Boost 4x: wrong sign" : "Audio Boost 2x: wrong sign", wrong, 0, 0);
            check(m ? "Audio Boost 4x: not monotonic" : "Audio Boost 2x: not monotonic", down, 0, 0);
        end
        if (errors) $display("%0d FAILURES", errors); else $display("ALL PASSED");
        $finish;
    end
endmodule
