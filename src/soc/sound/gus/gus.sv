// Gravis UltraSound for z486 (proof of concept).
//
// The GF1 chip model (gf1.v) and the register glue are xolod79's, from the GUS branch of
// ao486_MiSTer (https://github.com/xolod79/ao486_MiSTer, commit 98374e4, BSD licence like the
// rest of ao486's rtl). There the card owns the SDRAM module for its megabyte of sample memory.
// z486 keeps its main memory in the SDRAM, so here the sample memory sits behind a plain
// request/acknowledge port and may be anything: a shared DDR3 port, a slow bus.
//
// What makes that possible: the GF1 model is one synchronous block on the system clock and
// treats the chip's own 9.8784 MHz clock as a sampled signal, which this wrapper generates. The
// model asks for memory at two fixed phases of that clock and expects the data shortly after.
// The wrapper holds the chip clock while a request is outstanding and delivers the missed
// transitions afterwards at a faster rate (a level lasts two system clocks at least; the model
// runs with shorter ones in ao486 at 30 MHz). The memory's latency is then invisible to the
// chip, and the chip still makes its nominal number of clock transitions per second.
//
// Fixed resources as in ao486: I/O 240h-24Fh and 340h-34Fh, 16-bit DMA, one interrupt line.
//   ULTRASND=240,7,7,7,7

module gus #(parameter CLK_RATE = 85_000_000)
(
	input         clk,
	input         reset,
	input         enable,         // card present; off: no memory traffic, nothing driven

	input         io_address8,    // I/O address bit 8: 0 = 24xh, 1 = 34xh
	input   [3:0] io_address,
	input   [7:0] writedata,
	output  [7:0] readdata,
	input         gus_cs,
	input         fm_cs,          // AdLib ports: the GF1 watches the writes for its timer emulation
	input         write,
	input         read,
	output        io_wait,

	output        dma_req,
	input         dma_ack,
	input         dma_tc,
	input  [15:0] dma_readdata,
	output [15:0] dma_writedata,

	output        irq,

	output [15:0] audio_l,
	output [15:0] audio_r,

	// sample memory: one megabyte, byte addressed. mem_req is held, with everything else stable,
	// until mem_ack. mem_word: both bytes of the word at mem_addr (even) are written; otherwise
	// the byte at mem_addr, taken from mem_wdata[7:0]. A read returns the 16-bit word that
	// contains the byte (low byte = even address).
	output        mem_req,
	output        mem_we,
	output        mem_word,
	output [19:0] mem_addr,
	output [15:0] mem_wdata,
	input  [15:0] mem_rdata,
	input         mem_ack
);

//------------------------------------------------------------------------------ chip clock

// two transitions per cycle of 9,878,400 Hz
localparam [27:0] TICK2 = 28'd19_756_800;

reg  [27:0] acc = 0;
wire [28:0] acc_sum = acc + TICK2;
wire        tick    = (acc_sum >= CLK_RATE);

reg   [7:0] owed = 0;       // transitions due and not yet delivered
reg         gf1_clk2 = 0;
reg         spaced = 0;     // a transition was delivered in the previous cycle
wire        stall;
wire        deliver = (owed != 0) & ~stall & ~spaced;

always @(posedge clk) begin
	acc    <= tick ? acc_sum[27:0] - CLK_RATE[27:0] : acc_sum[27:0];
	spaced <= deliver;
	if (deliver) gf1_clk2 <= ~gf1_clk2;
	case ({tick, deliver})
		2'b10: if (~&owed) owed <= owed + 1'd1;   // a stall longer than 255 transitions loses time
		2'b01: owed <= owed - 1'd1;
		default: ;
	endcase
end

//------------------------------------------------------------------------------ sample memory

wire [19:0] dram_addr;
wire [15:0] DRAM_o;
reg  [15:0] DRAM_i;
wire        word;
wire        dram_access;
wire        dram_we;

// One request per access: the chip clock stands still from the moment the model raises
// dram_access until the memory has answered, so address and data are stable throughout.
reg served;
assign stall     = dram_access & ~served;
assign mem_req   = stall & enable;
assign mem_we    = dram_we;
assign mem_word  = word;
assign mem_addr  = dram_addr;
assign mem_wdata = DRAM_o;

always @(posedge clk) begin
	if (~dram_access) served <= 0;
	else if (~enable) served <= 1;
	else if (mem_ack) begin
		served <= 1;
		if (~dram_we) DRAM_i <= mem_rdata;
	end
end

//------------------------------------------------------------------------------ registers

wire       dreq;
wire       irq1;
wire       irq2;
wire       gf1_wait;
reg  [1:0] read_wait;
reg  [1:0] write_wait;
reg        read_d;
reg        write_d;
wire       gf1_read   = read  & gus_cs;
wire       gf1_write  = write & (gus_cs | fm_cs);
wire       read_cont  = (~read_d  & gf1_read)  | (|read_wait);
wire       write_cont = (~write_d & gf1_write) | (|write_wait);
assign     io_wait    = enable & (gf1_wait | read_cont | write_cont);

wire [7:0] readdata_gf1;
assign     readdata = isgf1addr ? readdata_gf1 : 8'hff;

wire isgf1addr = (gus_cs & (~io_address8        // 24xh
		& (io_address[3:0] == 4'h6 | io_address[3:0] == 4'h8 | io_address[3:0] == 4'h9 |
		   io_address[3:0] == 4'ha | io_address[3:0] == 4'hc | io_address[3:0] == 4'he)) |
		(io_address8                            // 34xh
		& (io_address[3:0] == 4'h0 | io_address[3:0] == 4'h1 | io_address[3:0] == 4'h2 |
		   io_address[3:0] == 4'h3 | io_address[3:0] == 4'h4 | io_address[3:0] == 4'h5 |
		   io_address[3:0] == 4'h7)) ) |
		fm_cs;
wire ismixeraddr = gus_cs & ~io_address8 & (io_address[3:0] == 4'h0);

reg  dmairq_regsel;
reg  dmairq_enable;
assign dma_req = dmairq_enable & dreq;
assign irq     = dmairq_enable & (irq1 | irq2);

gf1 gf1 (
	.MCLK          (clk),
	.CLK           (gf1_clk2),
	.IOW           (write_cont),
	.IOR           (read_cont),
	.CS1           (isgf1addr),
	.CS2           (1'b0),
	.ADDRESS       (io_address[3:0]),
	.DATA_i        (writedata),
	.DATA_o        (readdata_gf1),
	.dma_writedata (dma_writedata),
	.dma_readdata  (dma_readdata),
	.DRQ1          (dreq),
	.DACK1         (dma_ack),
	.IRQ1          (irq1),
	.IRQ2          (irq2),
	.RESET         (reset),
	.WAIT          (gf1_wait),
	.DMA_TC        (dma_tc),
	.dram_access   (dram_access),
	.dram_word     (word),
	.dram_addr     (dram_addr),
	.dram_refresh  (),
	.DRAM_DATA_i   (DRAM_i),
	.DRAM_DATA_o   (DRAM_o),
	.dram_we       (dram_we),
	.audio_l       (audio_l),
	.audio_r       (audio_r)
);

always @(posedge clk) begin
	read_d     <= gf1_read;
	write_d    <= gf1_write;
	read_wait  <= { read_wait[0],  (~read_d  & gf1_read)  ? 1'b1 : 1'b0 };
	write_wait <= { write_wait[0], (~write_d & gf1_write) ? 1'b1 : 1'b0 };

	if (ismixeraddr & write) begin
		dmairq_regsel <= writedata[6];
		dmairq_enable <= writedata[3];
	end
	if (reset) begin
		dmairq_regsel <= 0;
		dmairq_enable <= 0;
	end
end

endmodule
