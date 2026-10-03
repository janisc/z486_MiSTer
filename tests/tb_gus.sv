// Testbench for the GUS wrapper with its sample memory behind a slow port (gus.sv + gus_ddr.sv
// around xolod79's gf1.v): the DRAM poke and peek registers must work through a memory model
// with random waitrequest and random read latency, and the chip clock must keep its nominal
// rate on average while it waits for the memory.
//
//   python3 gus_sim_prep.py ../src/soc/sound/gus/gf1.v /tmp/gf1_sim.v
//   iverilog -g2012 -o /tmp/gus.vvp tb_gus.sv ../src/soc/sound/gus/gus.sv ../src/soc/sound/gus/gus_ddr.sv /tmp/gf1_sim.v
//   vvp /tmp/gus.vvp
`timescale 1ns/1ps

// behavioural stand-in for the altsyncram of gus_spram.v: registered address, unregistered
// output, new data on a read during a write
module spram #(parameter addr_width = 8, parameter data_width = 8)
(
	input                   clock,
	input  [addr_width-1:0] address,
	input  [data_width-1:0] data,
	input                   wren,
	output [data_width-1:0] q
);
	reg [data_width-1:0] mem [0:(1<<addr_width)-1];
	reg [addr_width-1:0] a_r = 0;
	integer k;
	initial for (k = 0; k < (1<<addr_width); k = k + 1) mem[k] = 0;
	always @(posedge clock) begin
		if (wren) mem[address] <= data;
		a_r <= address;
	end
	assign q = mem[a_r];
endmodule

module tb_gus;

localparam CLK_RATE = 85_000_000;
localparam real CLK_PERIOD = 1000000000.0 / CLK_RATE;   // ns

reg clk = 0;
always #(CLK_PERIOD/2.0) clk = ~clk;

reg reset = 1;
reg enable = 0;

// ---------------------------------------------------------------- I/O bus as iobus_adapter drives it
reg  [15:0] io_address = 0;
reg   [7:0] io_writedata = 0;
reg         io_read = 0, io_write = 0;
reg         gus_cs = 0, fm_cs = 0;
wire  [7:0] readdata;
wire        io_wait;

reg         req_rd = 0, req_wr = 0;
reg  [15:0] req_port = 0;
reg   [7:0] req_data = 0;
reg         done = 0;
reg   [7:0] cap = 0;
reg   [7:0] early = 0;       // the data in the first clock without wait (where ao486's bus captures)
reg   [2:0] st = 0;
integer     wait_cycles = 0, wait_max = 0;

always @(posedge clk) begin
	io_read  <= 0;
	io_write <= 0;
	done     <= 0;
	case (st)
		0: if (req_rd | req_wr) begin                 // address load, selects registered with it
			io_address <= req_port;
			gus_cs <= (req_port[15:4] == 12'h024) || (req_port[15:4] == 12'h034);
			fm_cs  <= (req_port[15:2] == 14'h00E2);
			wait_cycles <= 0;
			st <= 1;
		end
		1: begin                                      // ISSUE
			if (req_rd) io_read <= 1;
			else begin io_write <= 1; io_writedata <= req_data; end
			st <= 2;
		end
		2: if (!io_wait) begin early <= readdata; st <= req_rd ? 3'd3 : 3'd4; end  // WAIT, held by the peripheral
		   else begin
			wait_cycles <= wait_cycles + 1;
			if (wait_cycles > 200000) begin $display("FAIL: io_wait stuck"); $finish; end
		end
		3: begin cap <= readdata; st <= 4; end        // CAP
		4: begin
			done <= 1; st <= 5;
			if (wait_cycles > wait_max) wait_max <= wait_cycles;
		end
		5: st <= 0;
	endcase
end

task io_wr(input [15:0] port, input [7:0] d);
begin
	@(posedge clk); req_port <= port; req_data <= d; req_wr <= 1;
	@(posedge done);
	@(posedge clk); req_wr <= 0;
	@(posedge clk);
end
endtask

task io_rd(input [15:0] port, output [7:0] d);
begin
	@(posedge clk); req_port <= port; req_rd <= 1;
	@(posedge done);
	d = cap;
	@(posedge clk); req_rd <= 0;
	@(posedge clk);
end
endtask

// ---------------------------------------------------------------- DMA controller as z486's engine serves a device
// (one word per request: memory read, then ack for one clock with the data, terminal count one
// clock after the ack of the last word, and the channel masks itself)
reg         dack = 0, dtc = 0;
reg  [15:0] dma_rd = 0;
reg   [2:0] dst = 0;
integer     dma_left = 0, dma_idx = 0, dma_lat = 0, dma_words_done = 0;
reg  [15:0] dma_pattern [0:255];
wire        dma_req;

always @(posedge clk) begin
	dack <= 0;
	dtc  <= 0;
	case (dst)
		0: if (dma_req && dma_left > 0) begin dst <= 1; dma_lat <= 2 + ($urandom % 6); end
		1: if (dma_lat == 0) begin dma_rd <= dma_pattern[dma_idx]; dack <= 1; dst <= 4; end
		   else dma_lat <= dma_lat - 1;
		4: begin
			if (dma_left == 1) dtc <= 1;
			dma_left <= dma_left - 1;
			dma_idx  <= dma_idx + 1;
			dma_words_done <= dma_words_done + 1;
			dst <= 5;
		end
		5: dst <= 0;
	endcase
end

// ---------------------------------------------------------------- GUS
wire        mem_req, mem_we, mem_word, mem_ack;
wire [19:0] mem_addr;
wire [15:0] mem_wdata, mem_rdata;
wire [15:0] audio_l, audio_r;
wire        irq;

gus #(.CLK_RATE(CLK_RATE)) dut
(
	.clk(clk), .reset(reset), .enable(enable),
	.io_address8(io_address[8]), .io_address(io_address[3:0]),
	.writedata(io_writedata), .readdata(readdata),
	.gus_cs(gus_cs), .fm_cs(fm_cs), .write(io_write), .read(io_read), .io_wait(io_wait),
	.dma_req(dma_req), .dma_ack(dack), .dma_tc(dtc), .dma_readdata(dma_rd), .dma_writedata(),
	.irq(irq), .audio_l(audio_l), .audio_r(audio_r),
	.mem_req(mem_req), .mem_we(mem_we), .mem_word(mem_word), .mem_addr(mem_addr),
	.mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
);

wire        active, ddr_rd, ddr_we;
wire [28:0] ddr_addr;
wire [63:0] ddr_din;
wire  [7:0] ddr_be;
reg         ddr_busy = 0;
reg  [63:0] ddr_dout = 0;
reg         ddr_dout_ready = 0;

gus_ddr mem
(
	.clk(clk), .reset(reset),
	.mem_req(mem_req), .mem_we(mem_we), .mem_word(mem_word), .mem_addr(mem_addr),
	.mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
	.start_ok(1'b1), .active(active),
	.ddr_addr(ddr_addr), .ddr_rd(ddr_rd), .ddr_we(ddr_we), .ddr_din(ddr_din), .ddr_be(ddr_be),
	.ddr_busy(ddr_busy), .ddr_dout(ddr_dout), .ddr_dout_ready(ddr_dout_ready)
);

// ---------------------------------------------------------------- DDR3 model: waitrequest and latency at random
localparam [28:0] BASE = {4'h3, 8'hE0, 17'd0};
reg [63:0] ddr [0:131071];
integer    busy_pct = 0, lat_max = 1;
integer    rd_count = 0, wr_count = 0, req_count = 0;
integer    resp_cnt = 0;
reg [16:0] resp_idx = 0;
reg        resp_pending = 0;
integer    j;
initial for (j = 0; j < 131072; j = j + 1) ddr[j] = 64'hDEADBEEF_0BADF00D ^ {j[15:0], j[15:0], j[15:0], j[15:0]};

always @(posedge clk) begin
	ddr_busy       <= ($urandom % 100) < busy_pct;
	ddr_dout_ready <= 0;
	if ((ddr_rd | ddr_we) && (ddr_addr[28:17] != BASE[28:17])) begin
		$display("FAIL: access outside the megabyte, address %h", ddr_addr); $finish;
	end
	if (ddr_rd & ddr_we) begin $display("FAIL: read and write together"); $finish; end
	if (ddr_rd & ~ddr_busy) begin
		if (resp_pending) begin $display("FAIL: second read before the first answer"); $finish; end
		resp_pending <= 1;
		resp_idx     <= ddr_addr[16:0];
		resp_cnt     <= 1 + ($urandom % lat_max);
		rd_count     <= rd_count + 1;
	end
	if (ddr_we & ~ddr_busy) begin
		for (j = 0; j < 8; j = j + 1)
			if (ddr_be[j]) ddr[ddr_addr[16:0]][j*8 +: 8] <= ddr_din[j*8 +: 8];
		wr_count <= wr_count + 1;
	end
	if (resp_pending) begin
		if (resp_cnt <= 1) begin
			ddr_dout       <= ddr[resp_idx];
			ddr_dout_ready <= 1;
			resp_pending   <= 0;
		end
		else resp_cnt <= resp_cnt - 1;
	end
end

reg mem_req_d = 0;
always @(posedge clk) begin
	mem_req_d <= mem_req;
	if (mem_req & ~mem_req_d) req_count <= req_count + 1;
end

// ---------------------------------------------------------------- chip clock rate
integer   transitions = 0;
reg       clk2_d = 0;
always @(posedge clk) begin
	clk2_d <= dut.gf1_clk2;
	if (clk2_d != dut.gf1_clk2) transitions <= transitions + 1;
end

// ---------------------------------------------------------------- GUS register access
task gus_reg8(input [7:0] r, input [7:0] v);
begin
	io_wr(16'h343, r);
	io_wr(16'h345, v);
end
endtask

task gus_addr(input [19:0] a);
begin
	io_wr(16'h343, 8'h43);
	io_wr(16'h344, a[7:0]);
	io_wr(16'h345, a[15:8]);
	io_wr(16'h343, 8'h44);
	io_wr(16'h345, {4'h0, a[19:16]});
end
endtask

task poke(input [19:0] a, input [7:0] v);
begin
	gus_addr(a);
	io_wr(16'h347, v);
end
endtask

task peek(input [19:0] a, output [7:0] v);
begin
	gus_addr(a);
	io_rd(16'h347, v);
end
endtask

integer    errors = 0;
integer    n;
integer    guard;
reg  [7:0] st41, st246;

// GF1 DMA upload as the Gravis SDK does it on a 16-bit channel with 8-bit samples: reg 42h =
// DMA address, reg 41h = control (enable, 16-bit channel, terminal count interrupt)
task dma_upload(input integer pct, input integer lat, input [15:0] reg42, input integer words, input [7:0] salt);
	reg [19:0] lin;
begin
	busy_pct = pct;
	lat_max  = lat;
	for (n = 0; n < words; n = n + 1) dma_pattern[n] = {8'(2*n+1) ^ salt, 8'(2*n) ^ salt};
	dma_idx = 0; dma_words_done = 0;
	io_wr(16'h240, 8'h08);                 // mix control: enable the IRQ/DMA latches
	io_wr(16'h343, 8'h42);
	io_wr(16'h344, reg42[7:0]);
	io_wr(16'h345, reg42[15:8]);
	dma_left = words;
	io_wr(16'h343, 8'h41);
	io_wr(16'h345, 8'h25);                 // enable | 16-bit channel | TC interrupt
	guard = 0;
	while (!irq && guard < 400000) begin @(posedge clk); guard = guard + 1; end
	if (!irq) begin
		errors = errors + 1;
		$display("  DMA upload busy %0d%% latency <=%0d: NO INTERRUPT after %0d clocks; words taken %0d of %0d, drq %b",
		         pct, lat, guard, dma_words_done, words, dma_req);
	end
	else begin
		repeat (400) @(posedge clk);       // the last word is written after the terminal count
		io_rd(16'h246, st246);
		io_wr(16'h343, 8'h41);
		io_rd(16'h345, st41);
		$display("  DMA upload busy %0d%% latency <=%0d: interrupt after %0d clocks, words %0d, status 246h=%02h reg41h=%02h",
		         pct, lat, guard, dma_words_done, st246, st41);
		if (!st246[7] || !st41[6]) begin errors = errors + 1; $display("  status bits wrong"); end
	end
	io_wr(16'h343, 8'h41);
	io_wr(16'h345, 8'h00);                 // DMA off
	// the bytes, read back through the peek register: word address a covers linear bytes
	// {a[19:18], a[16:0], 0} and the next
	lin = {reg42[15:14], reg42[12:0], 4'h0, 1'b0};
	for (n = 0; n < 2*words; n = n + 1) begin
		peek(lin + n, v);
		if (v !== (8'(n) ^ salt)) begin
			errors = errors + 1;
			if (errors < 40) $display("    byte %0d at %05h: read %02h, expected %02h", n, lin + n, v, 8'(n) ^ salt);
		end
	end
end
endtask
reg  [7:0] v;
reg [19:0] ta [0:11];
reg [19:0] pa;
reg  [7:0] tv [0:11];
integer    t0_tr;
real       t0, t1, rate;

task run_pass(input integer pct, input integer lat, input [7:0] salt);
begin
	busy_pct = pct;
	lat_max  = lat;
	for (n = 0; n < 12; n = n + 1) poke(ta[n], tv[n] ^ salt);
	for (n = 0; n < 12; n = n + 1) begin
		peek(ta[n], v);
		if (v !== (tv[n] ^ salt)) begin
			errors = errors + 1;
			$display("  MISMATCH at %05h: read %02h, expected %02h", ta[n], v, tv[n] ^ salt);
		end
	end
	// the bytes must sit where the chip's address says, in the 64-bit words of the model. The GF1
	// presents an 8-bit access as {a[19:18], a[16:8], a[17], a[7:0]} (its DRAM row/column wiring).
	for (n = 0; n < 12; n = n + 1) begin
		pa = {ta[n][19:18], ta[n][16:8], ta[n][17], ta[n][7:0]};
		if (ddr[pa[19:3]][pa[2:0]*8 +: 8] !== (tv[n] ^ salt)) begin
			errors = errors + 1;
			$display("  WRONG PLACE for %05h (chip address %05h): memory holds %02h", ta[n], pa, ddr[pa[19:3]][pa[2:0]*8 +: 8]);
		end
	end
	$display("pass busy %0d%% latency <=%0d: %0d errors so far, longest I/O wait %0d clocks", pct, lat, errors, wait_max);
end
endtask

initial begin
	ta[0]  = 20'h00000; tv[0]  = 8'hAA;
	ta[1]  = 20'h00001; tv[1]  = 8'h55;
	ta[2]  = 20'h00002; tv[2]  = 8'h12;
	ta[3]  = 20'h00007; tv[3]  = 8'h34;
	ta[4]  = 20'h00008; tv[4]  = 8'h56;
	ta[5]  = 20'h00100; tv[5]  = 8'h78;
	ta[6]  = 20'h3FFFF; tv[6]  = 8'h9A;
	ta[7]  = 20'h40000; tv[7]  = 8'hBC;
	ta[8]  = 20'h7FFFE; tv[8]  = 8'hDE;
	ta[9]  = 20'h80000; tv[9]  = 8'hF0;
	ta[10] = 20'hC0000; tv[10] = 8'h0F;
	ta[11] = 20'hFFFFF; tv[11] = 8'hC3;

	repeat (20) @(posedge clk);
	reset = 0; enable = 1;
	repeat (2000) @(posedge clk);

	// GF1 reset register: into reset, out of reset
	gus_reg8(8'h4C, 8'h00);
	repeat (4000) @(posedge clk);
	gus_reg8(8'h4C, 8'h01);
	repeat (4000) @(posedge clk);

	run_pass(0, 1, 8'h00);       // ideal memory: answers in the next clock
	run_pass(0, 12, 8'h11);      // DDR3-like latency
	run_pass(30, 12, 8'h22);     // with waitrequest
	run_pass(60, 40, 8'h33);     // a busy port

	// register reads: what the bus sees one clock after the wait ends (z486's adapter) against
	// the first clock without wait (ao486's bus)
	busy_pct = 30; lat_max = 12;
	io_wr(16'h342, 8'h00);                              // voice 0
	io_wr(16'h343, 8'h8F); io_rd(16'h345, v); $display("read 8Fh (IRQ source) at 345h: late %02h, early %02h", v, early);
	io_wr(16'h343, 8'h80); io_rd(16'h345, v); $display("read 80h (voice control) at 345h: late %02h, early %02h", v, early);
	io_wr(16'h343, 8'h8D); io_rd(16'h345, v); $display("read 8Dh (ramp control) at 345h: late %02h, early %02h", v, early);
	io_wr(16'h343, 8'h8A); io_rd(16'h344, v); $display("read 8Ah (current address high) low byte at 344h: late %02h, early %02h", v, early);
	io_wr(16'h343, 8'h4C); io_rd(16'h345, v); $display("read 4Ch at 345h: late %02h, early %02h", v, early);
	io_wr(16'h343, 8'h4C); io_rd(16'h344, v); $display("read 4Ch at 344h: late %02h, early %02h", v, early);
	io_rd(16'h246, v); $display("read 246h (IRQ status): late %02h, early %02h", v, early);

	dma_upload(0, 1, 16'h0010, 16, 8'h00);
	dma_upload(0, 12, 16'h0020, 16, 8'h40);
	dma_upload(30, 12, 16'h0030, 16, 8'h80);
	dma_upload(60, 40, 16'h0040, 16, 8'hC0);
	$display("after the DMA uploads: %0d errors", errors);

	// chip clock: nominal number of transitions per second while the memory is slow
	busy_pct = 30; lat_max = 12;
	t0 = $realtime; t0_tr = transitions;
	repeat (CLK_RATE / 200) @(posedge clk);          // 5 ms
	t1 = $realtime;
	rate = (transitions - t0_tr) / ((t1 - t0) * 1.0e-9);
	$display("chip clock: %0.0f transitions per second (nominal 19756800), memory requests %0d, bus reads %0d, bus writes %0d",
	         rate, req_count, rd_count, wr_count);
	if (rate < 19756800.0 * 0.999 || rate > 19756800.0 * 1.001) begin
		errors = errors + 1;
		$display("  chip clock rate off");
	end

	if (errors == 0) $display("PASS");
	else $display("FAIL: %0d errors", errors);
	$finish;
end

endmodule
