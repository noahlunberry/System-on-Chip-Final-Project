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

  localparam int INDEX_W = (NUM_ELEMENTS <= 1) ? 1 : $clog2(NUM_ELEMENTS);
  localparam int CYCLE_W = (REUSE_CYCLES <= 1) ? 1 : $clog2(REUSE_CYCLES);

  localparam logic [INDEX_W-1:0] LAST_IDX_C = NUM_ELEMENTS - 1;
  localparam logic [INDEX_W-1:0] ONE_IDX_C  = 1'b1;
  localparam logic [CYCLE_W-1:0] LAST_CYCLE_C = REUSE_CYCLES - 1;
  localparam logic [CYCLE_W-1:0] ONE_CYCLE_C  = 1'b1;

  // This buffer is intentionally specialized for two NUM_ELEMENTS-sized banks:
  // one bank can be replayed while the other bank is refilled.
  logic [ELEMENT_WIDTH-1:0] mem [0:1][0:NUM_ELEMENTS-1];

  logic [ELEMENT_WIDTH-1:0] rd_data_r;

  logic                     wr_bank_r, next_wr_bank;
  logic [INDEX_W-1:0]       wr_idx_r, next_wr_idx;

  logic                     rd_bank_r, next_rd_bank;
  logic [INDEX_W-1:0]       rd_idx_r, next_rd_idx;
  logic [CYCLE_W-1:0]       replay_cycle_r, next_replay_cycle;

  logic [1:0]               bank_full_r, next_bank_full;

  logic                     empty_r, next_empty;
  logic                     not_full_r, next_not_full;
  logic                     rd_ready_r, next_rd_ready;

  logic                     do_write;
  logic                     do_read;
  logic                     write_finishes_bank;
  logic                     read_finishes_bank;
  logic                     last_reuse;

  assign rd_data  = rd_data_r;
  assign empty    = empty_r;
  assign not_full = not_full_r;
  assign rd_ready = rd_ready_r;

  assign do_write = wr_en && not_full_r;
  assign do_read  = rd_en && rd_ready_r;

  assign write_finishes_bank = do_write && (wr_idx_r == LAST_IDX_C);
  assign read_finishes_bank  = do_read && (rd_idx_r == LAST_IDX_C);
  assign last_reuse          = (replay_cycle_r == LAST_CYCLE_C);

  always_comb begin
    next_wr_bank      = wr_bank_r;
    next_wr_idx       = wr_idx_r;
    next_rd_bank      = rd_bank_r;
    next_rd_idx       = rd_idx_r;
    next_replay_cycle = replay_cycle_r;
    next_bank_full    = bank_full_r;

    if (do_write) begin
      if (write_finishes_bank) begin
        next_bank_full[wr_bank_r] = 1'b1;
        next_wr_idx               = '0;
        next_wr_bank              = ~wr_bank_r;
      end else begin
        next_wr_idx = wr_idx_r + ONE_IDX_C;
      end
    end

    if (do_read) begin
      if (read_finishes_bank) begin
        next_rd_idx = '0;

        if (last_reuse) begin
          next_bank_full[rd_bank_r] = 1'b0;
          next_replay_cycle         = '0;
          next_rd_bank              = ~rd_bank_r;
        end else begin
          next_replay_cycle = replay_cycle_r + ONE_CYCLE_C;
        end
      end else begin
        next_rd_idx = rd_idx_r + ONE_IDX_C;
      end
    end

    next_rd_ready = next_bank_full[next_rd_bank];
    next_not_full = !next_bank_full[next_wr_bank];

    // The write bank is the only place where partial data can exist. Once a
    // bank fills, wr_bank_r flips to the other bank immediately.
    next_empty = !(|next_bank_full) && (next_wr_idx == '0);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_bank_r      <= 1'b0;
      wr_idx_r       <= '0;
      rd_bank_r      <= 1'b0;
      rd_idx_r       <= '0;
      replay_cycle_r <= '0;
      bank_full_r    <= '0;
      rd_data_r      <= '0;
      empty_r        <= 1'b1;
      not_full_r     <= 1'b1;
      rd_ready_r     <= 1'b0;
    end else begin
      wr_bank_r      <= next_wr_bank;
      wr_idx_r       <= next_wr_idx;
      rd_bank_r      <= next_rd_bank;
      rd_idx_r       <= next_rd_idx;
      replay_cycle_r <= next_replay_cycle;
      bank_full_r    <= next_bank_full;
      empty_r        <= next_empty;
      not_full_r     <= next_not_full;
      rd_ready_r     <= next_rd_ready;

      if (do_read) begin
        rd_data_r <= mem[rd_bank_r][rd_idx_r];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (do_write) begin
      mem[wr_bank_r][wr_idx_r] <= wr_data;
    end
  end

  initial begin
    if (NUM_ELEMENTS < 1) begin
      $fatal(1, "replay_buffer requires NUM_ELEMENTS >= 1");
    end
    if (REUSE_CYCLES < 1) begin
      $fatal(1, "replay_buffer requires REUSE_CYCLES >= 1");
    end
    if (BUFFER_DEPTH != (NUM_ELEMENTS * 2)) begin
      $fatal(1, "replay_buffer is specialized for BUFFER_DEPTH == 2 * NUM_ELEMENTS");
    end
  end

endmodule
