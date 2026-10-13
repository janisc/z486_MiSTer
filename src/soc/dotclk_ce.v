// dotclk_ce: one clk-domain enable per edge of an asynchronous dot clock.
//
// A 4-bit Gray counter advances on every dotclk edge. The clk side samples it
// through two flops and issues one enable for every step it is behind, at most
// one per clk cycle, so the number of enables equals the number of dot-clock
// edges over any length of time. The enables come in short bursts set by the
// synchronizer latency (two or three clk cycles), which a renderer that already
// takes one to four clocks per dot absorbs. Works for any dot rate below the clk
// rate (the catch-up never exceeds a few steps; 16 are available).
//
// valid = 0 holds the enable off and tracks the counter, so enables resume
// without a backlog when valid rises.
module dotclk_ce
(
	input            clk,       // the renderer's clock
	input            dotclk,    // the dot clock, asynchronous to clk
	input            valid,     // clk domain: follow dotclk
	output reg       ce         // one cycle per dot
);

// dot-clock domain: binary counter and its Gray code, registered together so
// the Gray value changes one bit at a time
reg [3:0] bcnt = 4'd0;
reg [3:0] gcnt = 4'd0;
always @(posedge dotclk) begin
	bcnt <= bcnt + 4'd1;
	gcnt <= (bcnt + 4'd1) ^ ((bcnt + 4'd1) >> 1);
end

// clk domain: two synchronizer stages, Gray back to binary
reg [3:0] gs1 = 4'd0, gs2 = 4'd0;
always @(posedge clk) begin
	gs1 <= gcnt;
	gs2 <= gs1;
end
wire [3:0] rb = {gs2[3], gs2[3] ^ gs2[2], gs2[3] ^ gs2[2] ^ gs2[1], gs2[3] ^ gs2[2] ^ gs2[1] ^ gs2[0]};

reg [3:0] done = 4'd0;      // steps already turned into enables
always @(posedge clk) begin
	ce <= 1'b0;
	if(!valid) done <= rb;
	else if(done != rb) begin
		ce   <= 1'b1;
		done <= done + 4'd1;
	end
end

endmodule
