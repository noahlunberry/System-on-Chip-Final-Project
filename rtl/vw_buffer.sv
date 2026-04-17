module vw_buffer #(
    parameter int MAX_WR_BYTES = 8,  // Maximum number of input bytes accepted in one cycle
    parameter int RD_BYTES     = 8   // Number of bytes emitted as one output word
) (
    input logic clk,
    input logic rst,

    // Write side: `wr_data` carries up to MAX_WR_BYTES packed bytes and
    // `total_bytes` says how many low bytes are valid this cycle.
    input logic                              wr_en,
    input logic [        MAX_WR_BYTES*8-1:0] wr_data,
    input logic [$clog2(MAX_WR_BYTES+1)-1:0] total_bytes,

    // Read side: pulse `rd_en` when one RD_BYTES word is ready and drive the
    // oldest buffered bytes on `rd_data`.
    output logic                  rd_en,
    output logic [RD_BYTES*8-1:0] rd_data
);
  localparam int DEPTH_BYTES = 2 * MAX_WR_BYTES;

  initial begin
    // The read width must keep up with the sustained write width.
    if (RD_BYTES < MAX_WR_BYTES) begin
      $fatal(1, "vw_buffer parameter error: RD_BYTES (%0d) must be >= MAX_WR_BYTES (%0d).", RD_BYTES,
             MAX_WR_BYTES);
    end

    // This fixed two-word buffer still needs to hold one full read word.
    if (DEPTH_BYTES < RD_BYTES) begin
      $fatal(1, "vw_buffer parameter error: fixed DEPTH_BYTES (%0d) must be >= RD_BYTES (%0d).", DEPTH_BYTES,
             RD_BYTES);
    end
  end

  localparam int PTR_W = (DEPTH_BYTES <= 1) ? 1 : $clog2(DEPTH_BYTES);
  localparam int CNT_W = $clog2(DEPTH_BYTES + 1);

  // Circular byte buffer plus read/write pointers.
  logic [DEPTH_BYTES*8-1:0] mem_data_r, next_mem_data;
  logic [PTR_W-1:0] wr_ptr_r, next_wr_ptr;
  logic [PTR_W-1:0] rd_ptr_r, next_rd_ptr;
  logic [CNT_W-1:0] count_r, next_count;

  always_comb begin
    logic [PTR_W-1:0] write_idx;
    logic [PTR_W-1:0] read_idx;
    logic do_read;
    logic [CNT_W:0] wr_bytes;
    logic [CNT_W:0] rd_bytes;
    logic [CNT_W:0] next_count_wide;

    next_mem_data = mem_data_r;
    next_wr_ptr   = wr_ptr_r;
    next_rd_ptr   = rd_ptr_r;
    next_count    = count_r;

    write_idx     = wr_ptr_r;
    read_idx      = rd_ptr_r;

    rd_en         = 1'b0;
    rd_data       = '0;

    // Only bytes already buffered at the start of the cycle can be read.
    do_read       = (count_r >= RD_BYTES);

    if (wr_en) begin
      for (int i = 0; i < MAX_WR_BYTES; i++) begin
        if (i < total_bytes) begin
          next_mem_data[write_idx*8+:8] = wr_data[i*8+:8];
          if (write_idx == DEPTH_BYTES - 1) write_idx = '0;
          else write_idx++;
        end
      end

      next_wr_ptr = write_idx;
    end

    if (do_read) begin
      rd_en = 1'b1;

      for (int i = 0; i < RD_BYTES; i++) begin
        rd_data[i*8+:8] = mem_data_r[read_idx*8+:8];

        if (read_idx == DEPTH_BYTES - 1) read_idx = '0;
        else read_idx++;
      end

      next_rd_ptr = read_idx;
    end

    wr_bytes        = wr_en ? total_bytes : 0;
    rd_bytes        = do_read ? RD_BYTES : 0;

    next_count_wide = count_r + wr_bytes - rd_bytes;
    next_count      = next_count_wide[CNT_W-1:0];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      // mem_data_r <= '0;
      wr_ptr_r <= '0;
      rd_ptr_r <= '0;
      count_r  <= '0;
    end else begin
      mem_data_r <= next_mem_data;
      wr_ptr_r   <= next_wr_ptr;
      rd_ptr_r   <= next_rd_ptr;
      count_r    <= next_count;
    end
  end

endmodule
