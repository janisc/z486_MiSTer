// dot_resync: re-times a raster from the renderer's clock to the dot clock.
//
// The renderer produces its raster (colour, syncs, blanking) one dot per dot
// enable in its own clock domain, at the dot rate on average but a cycle or so
// early or late each time (the enable is the dot-clock PLL's edge seen through a
// synchronizer, and a dot is 3.376 of its clocks at 25.175 MHz). This FIFO is
// written on every such enable and read at the dot clock, one entry per cycle,
// so every pixel, sync edge and blanking edge comes out on a dot-clock edge. A
// marker says which dot starts a pixel (every dot, or one in three in the 24bpp
// mode, where a pixel is three dots long) and comes out as rce, the framework's
// CE_PIXEL. Both rates come from the same PLL, so the fill level stays where it
// started, around 16 of 64 entries, give or take the enable's jitter. (A first
// version carried one entry per pixel and popped every third cycle in 24bpp; the
// renderer restarts its divide-by-three at every hsync and a line is not a
// multiple of three dots, so the two sides drifted a dot a line.)
//
// While the renderer is not slaved to the PLL (hold = 1: the PLL reprograms at
// a mode switch, or a geometry the PLL table has no rate for) the read side stops
// and keeps itself in the middle behind the writer, so pixels flow again from a
// centred FIFO as soon as the renderer follows the PLL: a blank moment at a mode
// switch, like a real card's. If the FIFO ever runs empty or nearly full while
// running (a rate difference that should not exist), the read side re-centres
// the same way and counts it in resyncs.
//
// The pointers cross the clock boundary as Gray codes registered in their own
// domain. A Gray code computed by logic from a binary counter shows other values
// for a moment while the counter's bits settle, and the other clock, which shares
// the PLL reference and therefore samples at the same phases line after line,
// picked up those moments as wrong fill levels: dropped pixels and ragged line
// starts on the CRT in some clock families (build 2 of 2026-10-13).
//
// The storage is written in one always block and read, unconditionally, in
// another, the form Quartus infers a dual-clock RAM block from (the read
// pointer's entry is never written, so the continuous read holds its value).
module dot_resync #(parameter WIDTH = 27)
(
	input                  wclk,     // the renderer's clock
	input                  wce,      // one dot is on wdata
	input                  wpix,     // ... and it is the first dot of a pixel
	input      [WIDTH-1:0] wdata,

	input                  rclk,     // the dot clock
	input                  hold,     // wclk domain: the renderer is not slaved to the dot clock, stop and stay centred
	output                 rce,      // the dot on rdata starts a pixel (CE_PIXEL)
	output     [WIDTH-1:0] rdata,
	output reg             running,  // 1 while pixels flow, 0 while re-centring
	output reg       [7:0] resyncs   // re-centrings so far (rclk domain)
);

localparam AW = 6;                  // 64 entries

function [AW:0] bin2gray;
	input [AW:0] b;
	bin2gray = b ^ (b >> 1);
endfunction

function [AW:0] gray2bin;
	input [AW:0] g;
	integer i;
	begin
		gray2bin[AW] = g[AW];
		for (i = AW - 1; i >= 0; i = i - 1) gray2bin[i] = gray2bin[i + 1] ^ g[i];
	end
endfunction

(* ramstyle = "M10K" *) reg [WIDTH:0] mem [0:(1 << AW) - 1];   // the marker above the data

// ---- write side
reg  [AW:0] wptr = 0;
reg  [AW:0] wptr_g = 0;             // wptr's Gray code, registered together with it
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [AW:0] rptr_g_w1 = 0;
reg  [AW:0] rptr_g_w2 = 0;
wire [AW:0] rptr_w = gray2bin(rptr_g_w2);
wire [AW:0] wocc = wptr - rptr_w;
wire        wfull = (wocc >= 7'd60);
wire        wen = wce && !wfull;
wire [AW:0] wptr_n = wptr + 1'd1;

always @(posedge wclk) begin
	if (wen) mem[wptr[AW-1:0]] <= {wpix, wdata};
end

always @(posedge wclk) begin
	rptr_g_w1 <= rptr_g;
	rptr_g_w2 <= rptr_g_w1;
	if (wen) begin
		wptr   <= wptr_n;
		wptr_g <= bin2gray(wptr_n);
	end
end

// ---- read side
reg  [AW:0] rptr = 0;
reg  [AW:0] rptr_g = 0;             // rptr's Gray code, registered together with it
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg  [AW:0] wptr_g_r1 = 0;
reg  [AW:0] wptr_g_r2 = 0;
wire [AW:0] wptr_r = gray2bin(wptr_g_r2);
wire [AW:0] occ = wptr_r - rptr;
wire [AW:0] rptr_n = rptr + 1'd1;
wire [AW:0] rptr_c = wptr_r - 7'd16; // the middle: 16 entries behind the writer
reg   [WIDTH:0] rdata_q;
reg         pop_q = 1'b0;          // an entry was put on rdata_q this cycle
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg         hold_r1 = 0;
reg         hold_r2 = 0;

always @(posedge rclk) begin
	rdata_q <= mem[rptr[AW-1:0]];
end
assign rdata = rdata_q[WIDTH-1:0];
assign rce   = pop_q & rdata_q[WIDTH];

initial begin
	running = 0;
	resyncs = 0;
end

always @(posedge rclk) begin
	wptr_g_r1 <= wptr_g;
	wptr_g_r2 <= wptr_g_r1;
	hold_r1   <= hold;
	hold_r2   <= hold_r1;
	pop_q <= 1'b0;
	if (!running || hold_r2) begin
		// re-centre on 16: jump back behind the writer when overfull, wait when underfull
		running <= 1'b0;
		if (occ > 7'd20) begin
			rptr   <= rptr_c;
			rptr_g <= bin2gray(rptr_c);
		end
		else if (occ >= 7'd12 && !hold_r2) running <= 1'b1;
	end
	else if (occ == 0 || occ >= 7'd56) begin
		// ran empty (the writer stalled) or nearly full (the writer is faster): re-centre
		running <= 1'b0;
		resyncs <= resyncs + 1'd1;
	end
	else begin
		rptr   <= rptr_n;
		rptr_g <= bin2gray(rptr_n);
		pop_q  <= 1'b1;
	end
end

endmodule
