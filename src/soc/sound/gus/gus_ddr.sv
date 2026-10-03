// GUS sample memory in the HPS DDR3: one megabyte of bytes from the 64-bit word address BASE on,
// read and written one beat at a time through a port shared with other masters.
//
// The last word read is kept, so further reads within the same eight bytes cost no bus cycle
// (the GF1 reads memory in every voice slot, also for voices that stand still).

module gus_ddr #(parameter [28:0] BASE = {4'h3, 8'hE0, 17'd0})   // byte address 3E00_0000h
(
	input             clk,
	input             reset,

	input             mem_req,
	input             mem_we,
	input             mem_word,
	input      [19:0] mem_addr,
	input      [15:0] mem_wdata,
	output reg [15:0] mem_rdata,
	output reg        mem_ack,

	input             start_ok,       // no other transfer is in flight on the port: one may start
	output            active,         // a request of this master is on the port, or its read data is due
	output     [28:0] ddr_addr,
	output            ddr_rd,
	output            ddr_we,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	input             ddr_busy,       // Avalon waitrequest as this master sees it
	input      [63:0] ddr_dout,
	input             ddr_dout_ready
);

localparam [1:0] S_IDLE = 2'd0, S_RD = 2'd1, S_RDW = 2'd2, S_WR = 2'd3;

reg  [1:0] state = S_IDLE;
reg [16:0] tag;
reg        tag_valid = 0;
reg [63:0] kept;

wire [16:0] widx = mem_addr[19:3];
wire  [5:0] lane = {mem_addr[2:1], 4'b0000};      // bit offset of the aligned 16-bit word
wire        hit  = tag_valid && (tag == widx);

// the transfer on the port is driven from registers loaded when it starts (the request itself is
// stable for the whole transfer, so the GF1's address logic stays off the port's paths)
reg [19:0] a_r;
reg [15:0] d_r;
reg        w_r;

assign active   = (state != S_IDLE);
assign ddr_addr = BASE | {12'd0, a_r[19:3]};
assign ddr_rd   = (state == S_RD);
assign ddr_we   = (state == S_WR);
assign ddr_be   = w_r ? (8'b0000_0011 << {a_r[2:1], 1'b0}) : (8'b0000_0001 << a_r[2:0]);
assign ddr_din  = w_r ? {4{d_r}} : {8{d_r[7:0]}};

integer i;
always @(posedge clk) begin
	mem_ack <= 1'b0;

	if (reset) begin
		state     <= S_IDLE;
		tag_valid <= 1'b0;
	end
	else case (state)
		S_IDLE:
			if (mem_req & ~mem_ack) begin
				if (~mem_we & hit) begin
					mem_rdata <= kept[lane +: 16];
					mem_ack   <= 1'b1;
				end
				else if (start_ok) begin
					a_r   <= mem_addr;
					d_r   <= mem_wdata;
					w_r   <= mem_word;
					state <= mem_we ? S_WR : S_RD;
				end
			end

		// Avalon-MM: the request is held until the port accepts it
		S_RD:
			if (~ddr_busy) state <= S_RDW;

		S_RDW:
			if (ddr_dout_ready) begin
				kept      <= ddr_dout;
				tag       <= widx;
				tag_valid <= 1'b1;
				mem_rdata <= ddr_dout[lane +: 16];
				mem_ack   <= 1'b1;
				state     <= S_IDLE;
			end

		S_WR:
			if (~ddr_busy) begin
				if (hit) begin
					for (i = 0; i < 8; i = i + 1)
						if (ddr_be[i]) kept[i*8 +: 8] <= ddr_din[i*8 +: 8];
				end
				mem_ack <= 1'b1;
				state   <= S_IDLE;
			end
	endcase
end

endmodule
