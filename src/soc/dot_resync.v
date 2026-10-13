// dot_resync: re-times a raster from the renderer's clock to the dot clock.
//
// The renderer produces one pixel (colour, syncs, blanking) per pixel enable in
// its own clock domain, at the dot rate on average but a cycle or so early or
// late each time (the enable is the dot-clock PLL's edge seen through a
// synchronizer, and a dot is 3.376 of its clocks at 25.175 MHz). This FIFO is
// written on every such enable and read at the dot clock, one pixel per cycle
// (or per three cycles in the 24bpp mode, where the renderer's enable is one
// per three dots), so every pixel, sync edge and blanking edge comes out on a
// dot-clock edge. Both rates come from the same PLL, so the fill level stays
// where it started, around 16 of 64 entries, give or take the enable's jitter.
//
// Any lasting rate difference (the renderer still on its fractional divider
// while the PLL reprograms at a mode switch, or a clock family change) runs the
// FIFO empty or full; the read side then stops, drains or waits back to the
// middle and restarts: a blank moment at a mode switch, and the resyncs counter
// shows it happened.
//
// The storage is written in one always block and read, unconditionally, in
// another, the form Quartus infers a dual-clock RAM block from (the read
// pointer's entry is never written, so the continuous read holds its value).
module dot_resync #(parameter WIDTH = 27)
(
	input                  wclk,     // the renderer's clock
	input                  wce,      // one pixel is on wdata
	input      [WIDTH-1:0] wdata,

	input                  rclk,     // the dot clock
	input                  rdiv3,    // 1: one pixel per three rclk cycles (24bpp); quasi-static
	output reg             rce,      // a pixel was put on rdata this cycle
	output     [WIDTH-1:0] rdata,
	output reg             running,  // 1 while pixels flow, 0 while re-centring
	output reg       [7:0] resyncs   // re-centrings so far (rclk domain)
);

localparam AW = 6;                  // 64 entries

function [AW:0] gray2bin;
	input [AW:0] g;
	integer i;
	begin
		gray2bin[AW] = g[AW];
		for (i = AW - 1; i >= 0; i = i - 1) gray2bin[i] = gray2bin[i + 1] ^ g[i];
	end
endfunction

(* ramstyle = "M10K" *) reg [WIDTH-1:0] mem [0:(1 << AW) - 1];

// ---- write side
reg  [AW:0] wptr = 0;
wire [AW:0] wptr_g = wptr ^ (wptr >> 1);
reg  [AW:0] rptr_g_w1 = 0, rptr_g_w2 = 0;
wire [AW:0] rptr_w = gray2bin(rptr_g_w2);
wire [AW:0] wocc = wptr - rptr_w;
wire        wfull = (wocc >= 7'd60);
wire        wen = wce && !wfull;

always @(posedge wclk) begin
	if (wen) mem[wptr[AW-1:0]] <= wdata;
end

always @(posedge wclk) begin
	rptr_g_w1 <= rptr_g;
	rptr_g_w2 <= rptr_g_w1;
	if (wen) wptr <= wptr + 1'd1;
end

// ---- read side
reg  [AW:0] rptr = 0;
wire [AW:0] rptr_g = rptr ^ (rptr >> 1);
reg  [AW:0] wptr_g_r1 = 0, wptr_g_r2 = 0;
wire [AW:0] wptr_r = gray2bin(wptr_g_r2);
wire [AW:0] occ = wptr_r - rptr;
reg   [1:0] div = 0;
reg [WIDTH-1:0] rdata_q;

always @(posedge rclk) begin
	rdata_q <= mem[rptr[AW-1:0]];
end
assign rdata = rdata_q;

initial begin
	running = 0;
	resyncs = 0;
	rce = 0;
end

always @(posedge rclk) begin
	wptr_g_r1 <= wptr_g;
	wptr_g_r2 <= wptr_g_r1;
	rce <= 1'b0;
	if (!running) begin
		// re-centre on 16: drain two a cycle when overfull, wait when underfull
		if (occ > 7'd20)      rptr <= rptr + 2'd2;
		else if (occ >= 7'd12) begin running <= 1'b1; div <= 2'd0; end
	end
	else if (occ == 0) begin
		running <= 1'b0;
		resyncs <= resyncs + 1'd1;
	end
	else if (!rdiv3 || div == 2'd2) begin
		rptr <= rptr + 1'd1;
		rce  <= 1'b1;
		div  <= 2'd0;
	end
	else div <= div + 1'd1;
end

endmodule
