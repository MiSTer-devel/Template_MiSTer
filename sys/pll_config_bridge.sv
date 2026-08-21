// Written by Videodr0me.
// Queues HDMI PLL writes across clock domains and preserves backpressure.
module pll_config_bridge #(
	parameter integer FIFO_ADDR_W = 4
)(
	input  wire        src_clk,
	input  wire        reset,
	input  wire        src_valid,
	input  wire  [5:0] src_address,
	input  wire [31:0] src_data,
	input  wire        src_start,
	output logic       src_overflow = 1'b0,

	input  wire        dst_clk,
	input  wire        dst_waitrequest,
	output logic       dst_write = 1'b0,
	output logic [5:0] dst_address = '0,
	output logic [31:0] dst_data = '0,
	output logic       ready = 1'b0
);

	localparam integer FIFO_DEPTH = 1 << FIFO_ADDR_W;
	localparam integer PTR_W = FIFO_ADDR_W + 1;

	logic [37:0] fifo_mem [0:FIFO_DEPTH-1];
	logic [PTR_W-1:0] wr_bin = '0, wr_gray = '0;
	logic [PTR_W-1:0] rd_bin = '0, rd_gray = '0;

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [PTR_W-1:0] rd_gray_src_meta = '0, rd_gray_src = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [PTR_W-1:0] wr_gray_dst_meta = '0, wr_gray_dst = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic start_dst_meta = 1'b0, start_dst = 1'b0;

	wire [PTR_W-1:0] wr_bin_next = wr_bin + 1'b1;
	wire [PTR_W-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
	wire [PTR_W-1:0] rd_bin_next = rd_bin + 1'b1;
	wire [PTR_W-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
	wire [PTR_W-1:0] rd_gray_full = {
		~rd_gray_src[PTR_W-1:PTR_W-2], rd_gray_src[PTR_W-3:0]
	};
	wire fifo_full_src = (wr_gray == rd_gray_full);
	wire fifo_empty_src = (wr_gray == rd_gray_src);
	wire fifo_empty_dst = (rd_gray == wr_gray_dst);

	logic start_sent = 1'b0, start_toggle = 1'b0;
	always_ff @(posedge src_clk or posedge reset) begin
		if (reset) begin
			wr_bin           <= '0;
			wr_gray          <= '0;
			rd_gray_src_meta <= '0;
			rd_gray_src      <= '0;
			start_sent       <= 1'b0;
			start_toggle     <= 1'b0;
			src_overflow     <= 1'b0;
		end
		else begin
			rd_gray_src_meta <= rd_gray;
			rd_gray_src      <= rd_gray_src_meta;

			if (src_valid) begin
				if (!fifo_full_src) begin
					fifo_mem[wr_bin[FIFO_ADDR_W-1:0]] <= {src_address, src_data};
					wr_bin  <= wr_bin_next;
					wr_gray <= wr_gray_next;
				end
				else begin
					src_overflow <= 1'b1;
				end
			end

			if (!src_start) begin
				start_sent <= 1'b0;
			end
			// Commit only after every register write has been accepted downstream.
			else if (!start_sent && !src_valid && fifo_empty_src && !src_overflow) begin
				start_toggle <= ~start_toggle;
				start_sent   <= 1'b1;
			end
		end
	end

	logic start_dst_last = 1'b0, start_pending = 1'b0;
	logic dst_is_start = 1'b0, start_wait = 1'b0, wait_seen = 1'b0;
	always_ff @(posedge dst_clk or posedge reset) begin
		if (reset) begin
			rd_bin           <= '0;
			rd_gray          <= '0;
			wr_gray_dst_meta <= '0;
			wr_gray_dst      <= '0;
			start_dst_meta   <= 1'b0;
			start_dst        <= 1'b0;
			start_dst_last   <= 1'b0;
			start_pending    <= 1'b0;
			dst_write        <= 1'b0;
			dst_address      <= '0;
			dst_data         <= '0;
			dst_is_start     <= 1'b0;
			start_wait       <= 1'b0;
			wait_seen        <= 1'b0;
			ready            <= 1'b0;
		end
		else begin
			wr_gray_dst_meta <= wr_gray;
			wr_gray_dst      <= wr_gray_dst_meta;
			start_dst_meta   <= start_toggle;
			start_dst        <= start_dst_meta;

			if (start_dst != start_dst_last) begin
				start_dst_last <= start_dst;
				start_pending  <= 1'b1;
			end

			if (dst_write && !dst_waitrequest) begin
				dst_write <= 1'b0;
				if (dst_is_start) begin
					dst_is_start <= 1'b0;
					start_wait   <= 1'b1;
					wait_seen    <= 1'b0;
				end
				else begin
					rd_bin  <= rd_bin_next;
					rd_gray <= rd_gray_next;
				end
			end
			else if (!dst_write) begin
				if (!fifo_empty_dst) begin
					{dst_address, dst_data} <= fifo_mem[rd_bin[FIFO_ADDR_W-1:0]];
					dst_is_start <= 1'b0;
					dst_write    <= 1'b1;
				end
				else if (start_pending) begin
					dst_address   <= 6'd2;
					dst_data      <= 32'd0;
					dst_is_start  <= 1'b1;
					dst_write     <= 1'b1;
					start_pending <= 1'b0;
				end
			end

			if (start_wait) begin
				if (dst_waitrequest) begin
					wait_seen <= 1'b1;
				end
				else if (wait_seen) begin
					start_wait <= 1'b0;
					wait_seen  <= 1'b0;
					ready      <= 1'b1;
				end
			end
		end
	end

endmodule
