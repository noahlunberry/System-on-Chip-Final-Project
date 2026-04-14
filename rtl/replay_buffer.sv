module replay_buffer #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128,
    parameter int REUSE_CYCLES  = 1,
    parameter int BUFFER_DEPTH  = NUM_ELEMENTS * 2
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

  localparam bit DEPTH_IS_POW2 =
      (BUFFER_DEPTH > 0) && ((BUFFER_DEPTH & (BUFFER_DEPTH - 1)) == 0);

  localparam logic [CNT_W-1:0] BUFFER_DEPTH_C = BUFFER_DEPTH;
  localparam logic [CNT_W-1:0] NUM_ELEMENTS_C = NUM_ELEMENTS;
  localparam logic [CNT_W-1:0] ONE_CNT_C      = 1'b1;

  localparam logic [OFFSET_W-1:0] LAST_OFFSET_C = NUM_ELEMENTS - 1;
  localparam logic [OFFSET_W-1:0] ONE_OFFSET_C  = 1'b1;

  localparam logic [CYCLE_W-1:0] LAST_CYCLE_C = REUSE_CYCLES - 1;
  localparam logic [CYCLE_W-1:0] ONE_CYCLE_C  = 1'b1;

  localparam logic [PTR_W:0] ONE_PTR_C        = 1'b1;
  localparam logic [PTR_W:0] BLOCK_SIZE_PTR_C = NUM_ELEMENTS;
  localparam logic [PTR_W:0] DEPTH_PTR_C      = BUFFER_DEPTH;

  logic [ELEMENT_WIDTH-1:0] mem [0:BUFFER_DEPTH-1];

  logic [ELEMENT_WIDTH-1:0] rd_data_r;

  logic [PTR_W-1:0]    wr_ptr_r,    next_wr_ptr;
  logic [PTR_W-1:0]    rd_ptr_r,    next_rd_ptr;
  logic [PTR_W-1:0]    rd_base_r,   next_rd_base;
  logic [OFFSET_W-1:0] rd_offset_r, next_rd_offset;
  logic [CYCLE_W-1:0]  cycle_r,     next_cycle;
  logic [CNT_W-1:0]    elements_r,  next_elements;

  logic do_write;
  logic do_read;
  logic end_of_block;
  logic last_reuse;
  logic discard_block;

  logic [PTR_W-1:0] wr_ptr_inc;
  logic [PTR_W-1:0] rd_ptr_inc;
  logic [PTR_W-1:0] rd_base_next_block;

  function automatic logic [PTR_W-1:0] wrap_add(
      input logic [PTR_W-1:0] ptr,
      input logic [PTR_W:0]   inc
  );
    logic [PTR_W:0] sum;
    logic [PTR_W:0] wrapped_sum;
    begin
      if (DEPTH_IS_POW2) begin
        wrap_add = ptr + inc[PTR_W-1:0];
      end else begin
        sum         = {1'b0, ptr} + inc;
        wrapped_sum = sum - DEPTH_PTR_C;
        wrap_add    = (sum >= DEPTH_PTR_C) ? wrapped_sum[PTR_W-1:0]
                                           : sum[PTR_W-1:0];
      end
    end
  endfunction

  assign wr_ptr_inc         = wrap_add(wr_ptr_r, ONE_PTR_C);
  assign rd_ptr_inc         = wrap_add(rd_ptr_r, ONE_PTR_C);
  assign rd_base_next_block = wrap_add(rd_base_r, BLOCK_SIZE_PTR_C);

  assign empty    = (elements_r == '0);
  assign not_full = (elements_r != BUFFER_DEPTH_C);
  assign rd_ready = (elements_r >= NUM_ELEMENTS_C);
  assign rd_data  = rd_data_r;

  assign do_write      = wr_en && not_full;
  assign do_read       = rd_en && rd_ready;
  assign end_of_block  = do_read && (rd_offset_r == LAST_OFFSET_C);
  assign last_reuse    = (cycle_r == LAST_CYCLE_C);
  assign discard_block = end_of_block && last_reuse;

  always_comb begin
    next_wr_ptr    = wr_ptr_r;
    next_rd_ptr    = rd_ptr_r;
    next_rd_base   = rd_base_r;
    next_rd_offset = rd_offset_r;
    next_cycle     = cycle_r;
    next_elements  = elements_r;

    if (do_write) begin
      next_wr_ptr = wr_ptr_inc;
    end

    if (do_read) begin
      if (end_of_block) begin
        next_rd_offset = '0;

        if (last_reuse) begin
          next_cycle   = '0;
          next_rd_base = rd_base_next_block;
          next_rd_ptr  = rd_base_next_block;
        end else begin
          next_cycle  = cycle_r + ONE_CYCLE_C;
          next_rd_ptr = rd_base_r;
        end
      end else begin
        next_rd_offset = rd_offset_r + ONE_OFFSET_C;
        next_rd_ptr    = rd_ptr_inc;
      end
    end

    unique case ({do_write, discard_block})
      2'b10: next_elements = elements_r + ONE_CNT_C;
      2'b01: next_elements = elements_r - NUM_ELEMENTS_C;
      2'b11: next_elements = elements_r + ONE_CNT_C - NUM_ELEMENTS_C;
      default: begin
        // hold
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_ptr_r    <= '0;
      rd_ptr_r    <= '0;
      rd_base_r   <= '0;
      rd_offset_r <= '0;
      cycle_r     <= '0;
      elements_r  <= '0;
      rd_data_r   <= '0;
    end else begin
      wr_ptr_r    <= next_wr_ptr;
      rd_ptr_r    <= next_rd_ptr;
      rd_base_r   <= next_rd_base;
      rd_offset_r <= next_rd_offset;
      cycle_r     <= next_cycle;
      elements_r  <= next_elements;

      // Kept here intentionally so synthesis can infer a synchronous read path
      // more cleanly than if this were moved into always_comb.
      if (do_read) begin
        rd_data_r <= mem[rd_ptr_r];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (do_write) begin
      mem[wr_ptr_r] <= wr_data;
    end
  end

endmodule