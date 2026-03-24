module replay_buffer #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128,
    parameter int REUSE_CYCLES  = 1,
    localparam int BUFFER_DEPTH  = NUM_ELEMENTS * 8
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     wr_en,
    input  logic                     rd_en,
    input  logic [ELEMENT_WIDTH-1:0] wr_data,
    output logic [ELEMENT_WIDTH-1:0] rd_data,
    output logic                     empty,
    output logic                     not_full,
    output logic                     rd_ready
);

  localparam int PTR_W    = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH);
  localparam int CNT_W    = (BUFFER_DEPTH <= 1) ? 1 : $clog2(BUFFER_DEPTH + 1);
  localparam int OFFSET_W = (NUM_ELEMENTS <= 1) ? 1 : $clog2(NUM_ELEMENTS);
  localparam int CYCLE_W  = (REUSE_CYCLES <= 1) ? 1 : $clog2(REUSE_CYCLES);

  logic [ELEMENT_WIDTH-1:0] mem [BUFFER_DEPTH];
  logic [ELEMENT_WIDTH-1:0] rd_data_r, next_rd_data;
  
  logic [PTR_W-1:0]    wr_ptr,    next_wr_ptr;
  logic [PTR_W-1:0]    rd_base,   next_rd_base;
  logic [OFFSET_W-1:0] rd_offset, next_rd_offset;
  logic [CYCLE_W-1:0]  cycle_r,   next_cycle;
  logic [CNT_W-1:0]    elements,  next_elements;

  logic do_write;
  logic do_read;
  logic block_complete;

  assign not_full = (elements < BUFFER_DEPTH);
  assign rd_ready     = (elements >= NUM_ELEMENTS);
  assign empty    = (elements == 0);
  assign rd_data  = rd_data_r;

  assign do_write = wr_en && not_full;
  assign do_read  = rd_en && rd_ready;
  assign block_complete = do_read && (rd_offset == NUM_ELEMENTS - 1) && (cycle_r == REUSE_CYCLES - 1);

  // Address generation for the sliding window read
  int virt_rd_addr;
  logic [PTR_W-1:0] active_rd_addr;
  assign virt_rd_addr = int'(rd_base) + int'(rd_offset);
  assign active_rd_addr = (virt_rd_addr >= BUFFER_DEPTH) ? PTR_W'(virt_rd_addr - BUFFER_DEPTH) : PTR_W'(virt_rd_addr);

  always_comb begin
    next_wr_ptr    = wr_ptr;
    next_rd_base   = rd_base;
    next_rd_offset = rd_offset;
    next_cycle     = cycle_r;
    next_elements  = elements;
    next_rd_data   = rd_data_r;

    // Track Fill Capacity
    if (do_write && block_complete) begin
       next_elements = elements + CNT_W'(1) - CNT_W'(NUM_ELEMENTS);
    end else if (do_write) begin
       next_elements = elements + CNT_W'(1);
    end else if (block_complete) begin
       next_elements = elements - CNT_W'(NUM_ELEMENTS);
    end

    // Advance Write Pointer
    if (do_write) begin
       next_wr_ptr = (wr_ptr == BUFFER_DEPTH - 1) ? '0 : wr_ptr + 1;
    end

    // Advance Read Sliding Window
    if (do_read) begin
       next_rd_data = mem[active_rd_addr];

       if (rd_offset == NUM_ELEMENTS - 1) begin
           next_rd_offset = '0;
           if (cycle_r == REUSE_CYCLES - 1) begin
               next_cycle = '0;
               // Shift the base pointer boundary to permanently discard the used data block
               if (int'(rd_base) + NUM_ELEMENTS >= BUFFER_DEPTH) begin
                   next_rd_base = PTR_W'(int'(rd_base) + NUM_ELEMENTS - BUFFER_DEPTH);
               end else begin
                   next_rd_base = PTR_W'(rd_base + NUM_ELEMENTS);
               end
           end else begin
               next_cycle = cycle_r + 1;
           end
       end else begin
           next_rd_offset = rd_offset + 1;
       end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr     <= '0;
      rd_base    <= '0;
      rd_offset  <= '0;
      cycle_r    <= '0;
      elements   <= '0;
      rd_data_r  <= '0;
    end else begin
      wr_ptr     <= next_wr_ptr;
      rd_base    <= next_rd_base;
      rd_offset  <= next_rd_offset;
      cycle_r    <= next_cycle;
      elements   <= next_elements;
      rd_data_r  <= next_rd_data;
    end
  end

  // Synchronous Ring Buffer Writes
  always_ff @(posedge clk) begin
    if (do_write) begin
       mem[wr_ptr] <= wr_data;
    end
  end

endmodule
