module vw_buffer #(
    parameter int MAX_WR_BYTES = 8,  // Maximum number of input bytes accepted in one cycle
    parameter int RD_BYTES     = 8   // Number of bytes emitted as one output word
) (
    input logic clk,
    input logic rst,

    // Write-side interface:
    //
    // wr_en:
    //   Indicates that wr_data contains valid incoming bytes this cycle.
    //
    // wr_data:
    //   Flat packed bus containing up to MAX_WR_BYTES bytes.
    //   Byte 0 is wr_data[7:0], byte 1 is wr_data[15:8], etc.
    //
    // total_bytes:
    //   Tells the module how many of the low bytes of wr_data are valid this cycle.
    input logic                              wr_en,
    input logic [        MAX_WR_BYTES*8-1:0] wr_data,
    input logic [$clog2(MAX_WR_BYTES+1)-1:0] total_bytes,

    // Read-side interface:
    //
    // rd_en:
    //   Pulses high whenever at least RD_BYTES were already buffered at the
    //   start of the cycle, meaning one output word can be produced.
    //
    // rd_data:
    //   Contains the oldest RD_BYTES currently buffered.
    output logic                  rd_en,
    output logic [RD_BYTES*8-1:0] rd_data
);
  localparam int DEPTH_BYTES = 2 * MAX_WR_BYTES;

  initial begin
    // To avoid long-term overflow, the sustained read bandwidth must be
    // at least the sustained write bandwidth.
    if (RD_BYTES < MAX_WR_BYTES) begin
      $fatal(1, "vw_buffer parameter error: RD_BYTES (%0d) must be >= MAX_WR_BYTES (%0d).",
             RD_BYTES, MAX_WR_BYTES);
    end

    // This implementation always stores exactly two write-width words. That
    // fixed storage still needs to be large enough to hold at least one full
    // read word.
    if (DEPTH_BYTES < RD_BYTES) begin
      $fatal(1, "vw_buffer parameter error: fixed DEPTH_BYTES (%0d) must be >= RD_BYTES (%0d).",
             DEPTH_BYTES, RD_BYTES);
    end
  end

  // Pointer width needed to address DEPTH_BYTES entries in the circular buffer.
  localparam int PTR_W = (DEPTH_BYTES <= 1) ? 1 : $clog2(DEPTH_BYTES);

  // Count width needed to represent 0 through DEPTH_BYTES valid buffered bytes.
  localparam int CNT_W = $clog2(DEPTH_BYTES + 1);

  // --------------------------------------------------------------------------
  // Registered state
  // --------------------------------------------------------------------------

  // Flat packed byte storage for the circular buffer.
  //
  // Byte i lives at:
  //   mem_data_r[i*8 +: 8]
  //
  // This buffer is never physically shifted. Instead, write and read pointers
  // walk around it circularly.
  logic [DEPTH_BYTES*8-1:0] mem_data_r, next_mem_data;

  // Write pointer:
  //   Points to the location where the next incoming byte will be written.
  logic [PTR_W-1:0] wr_ptr_r, next_wr_ptr;

  // Read pointer:
  //   Points to the oldest unread byte currently stored in the buffer.
  logic [PTR_W-1:0] rd_ptr_r, next_rd_ptr;

  // Count of how many valid bytes are currently buffered.
  logic [CNT_W-1:0] count_r, next_count;

  // --------------------------------------------------------------------------
  // Combinational next-state / output logic
  // --------------------------------------------------------------------------
  always_comb begin
    // Temporary cursor used to step through byte locations while writing
    // multiple bytes in the same cycle. This starts from the registered write
    // pointer and wraps as needed.
    logic [PTR_W-1:0] write_idx;

    // Temporary cursor used to step through byte locations while reading out
    // RD_BYTES bytes in the same cycle. This starts from the registered read
    // pointer and wraps as needed.
    logic [PTR_W-1:0] read_idx;

    // Whether a read should occur this cycle.
    //
    // Important:
    // This is based only on the registered count from the start of the cycle.
    // That means newly written bytes from this same cycle do NOT immediately
    // make the buffer readable in the same cycle.
    logic do_read;

    // Number of bytes written this cycle.
    logic [CNT_W:0] wr_bytes;

    // Number of bytes read this cycle.
    logic [CNT_W:0] rd_bytes;

    // Wide temporary used to compute the next occupancy count without risking
    // intermediate truncation.
    logic [CNT_W:0] next_count_wide;

    // ------------------------------------------------------------------------
    // Default assignments
    // ------------------------------------------------------------------------
    // Hold state unless changed below.
    next_mem_data = mem_data_r;
    next_wr_ptr   = wr_ptr_r;
    next_rd_ptr   = rd_ptr_r;
    next_count    = count_r;

    // Default the temporary cursors to the registered pointer values.
    write_idx     = wr_ptr_r;
    read_idx      = rd_ptr_r;

    // Default outputs.
    rd_en         = 1'b0;
    rd_data       = '0;

    // ------------------------------------------------------------------------
    // Read decision
    // ------------------------------------------------------------------------
    // A read occurs only if there were already enough buffered bytes at the
    // start of the cycle to form one full output word.
    do_read       = (count_r >= RD_BYTES);

    // ------------------------------------------------------------------------
    // WRITE SIDE
    // ------------------------------------------------------------------------
    // If wr_en is asserted, write total_bytes bytes into the circular buffer.
    //
    // The writes begin at wr_ptr_r and advance one byte location at a time,
    // wrapping back to 0 when the end of the buffer is reached.
    //
    // Because the write pointer is explicit, the module naturally writes to:
    //   ..., DEPTH_BYTES-2, DEPTH_BYTES-1, 0, 1, 2, ...
    //
    if (wr_en) begin
      for (int i = 0; i < MAX_WR_BYTES; i++) begin
        if (i < total_bytes) begin
          // Write incoming byte i into the current circular-buffer location.
          next_mem_data[write_idx*8+:8] = wr_data[i*8+:8];

          // Advance the temporary write cursor with wraparound.
          if (write_idx == DEPTH_BYTES - 1) write_idx = '0;
          else write_idx++;
        end
      end

      // After all bytes of this cycle have been written, store the final
      // position as the starting write pointer for the next cycle.
      next_wr_ptr = write_idx;
    end

    // ------------------------------------------------------------------------
    // READ SIDE
    // ------------------------------------------------------------------------
    // If enough bytes were already buffered at the start of the cycle, emit one
    // output word consisting of the oldest RD_BYTES bytes.
    //
    // These bytes come from mem_data_r (the registered buffer contents), not
    // next_mem_data. This keeps the read path based only on registered state
    // and avoids same-cycle dependence on newly written data.
    if (do_read) begin
      rd_en = 1'b1;

      for (int i = 0; i < RD_BYTES; i++) begin
        // Copy the current oldest byte into the appropriate position in rd_data.
        rd_data[i*8+:8] = mem_data_r[read_idx*8+:8];

        // Advance the temporary read cursor with wraparound.
        if (read_idx == DEPTH_BYTES - 1) read_idx = '0;
        else read_idx++;
      end

      // After consuming RD_BYTES bytes, store the resulting position as the
      // starting read pointer for the next cycle.
      next_rd_ptr = read_idx;
    end

    // ------------------------------------------------------------------------
    // Occupancy update
    // ------------------------------------------------------------------------
    // The buffer count tracks how many valid bytes will be stored next cycle.
    //
    // Even though the read decision is based only on registered count_r, the
    // final next count still includes both operations from this cycle:
    //   - bytes written this cycle
    //   - bytes read this cycle
    //
    // So if both happen together, next_count becomes:
    //   count_r + total_bytes - RD_BYTES
    //
    // wr_bytes and rd_bytes make that arithmetic explicit and easy to follow.
    wr_bytes        = wr_en ? total_bytes : 0;
    rd_bytes        = do_read ? RD_BYTES : 0;

    next_count_wide = count_r + wr_bytes - rd_bytes;
    next_count      = next_count_wide[CNT_W-1:0];
  end

  // --------------------------------------------------------------------------
  // Sequential state update
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      mem_data_r <= '0;
      wr_ptr_r   <= '0;
      rd_ptr_r   <= '0;
      count_r    <= '0;
    end else begin
      mem_data_r <= next_mem_data;
      wr_ptr_r   <= next_wr_ptr;
      rd_ptr_r   <= next_rd_ptr;
      count_r    <= next_count;
    end
  end

endmodule
