module replay_srl_bank #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128
) (
    input  logic                     clk,
    input  logic                     shift_en,
    input  logic [ELEMENT_WIDTH-1:0] shift_in,
    output logic [ELEMENT_WIDTH-1:0] shift_out
);

  // No reset on the storage array. That is important for clean SRL inference.
  if (NUM_ELEMENTS == 1) begin : gen_depth1
    logic [ELEMENT_WIDTH-1:0] shreg_r;

    assign shift_out = shreg_r;

    always_ff @(posedge clk) begin
      if (shift_en) begin
        shreg_r <= shift_in;
      end
    end
  end else begin : gen_depthn
    localparam int TOTAL_W = ELEMENT_WIDTH * NUM_ELEMENTS;

    (* shreg_extract = "yes", srl_style = "srl" *)
    logic [TOTAL_W-1:0] shreg_r;

    // Tail word = oldest word in the bank
    assign shift_out = shreg_r[TOTAL_W-1 -: ELEMENT_WIDTH];

    always_ff @(posedge clk) begin
      if (shift_en) begin
        shreg_r <= {shreg_r[TOTAL_W-ELEMENT_WIDTH-1:0], shift_in};
      end
    end
  end

endmodule


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

  localparam logic [INDEX_W-1:0] LAST_IDX_C   = NUM_ELEMENTS - 1;
  localparam logic [CYCLE_W-1:0] LAST_CYCLE_C = REUSE_CYCLES - 1;

  logic [ELEMENT_WIDTH-1:0] rd_data_r;

  logic                     wr_bank_r, next_wr_bank;
  logic [INDEX_W-1:0]       wr_idx_r,  next_wr_idx;

  logic                     rd_bank_r, next_rd_bank;
  logic [INDEX_W-1:0]       rd_idx_r,  next_rd_idx;
  logic [CYCLE_W-1:0]       replay_cycle_r, next_replay_cycle;

  logic [1:0]               bank_full_r, next_bank_full;

  logic                     do_write;
  logic                     do_read;

  logic [ELEMENT_WIDTH-1:0] bank_shift_in  [0:1];
  logic [ELEMENT_WIDTH-1:0] bank_shift_out [0:1];
  logic [1:0]               bank_shift_en;

  assign rd_data   = rd_data_r;

  // Best-timing version: decode status directly from current registered state

  assign rd_ready = bank_full_r[rd_bank_r];
  assign not_full = !bank_full_r[wr_bank_r];
  assign empty    = !(|bank_full_r) && (wr_idx_r == '0);

  assign do_write = wr_en && not_full;
  assign do_read  = rd_en && rd_ready;

  // --------------------------------------------------------------------------
  // SRL bank datapath
  //
  // Fill behavior:
  //   shift in wr_data on the active write bank
  //
  // Replay behavior:
  //   shift the current tail word back into the same bank, which rotates the
  //   bank and preserves the original read order on the next cycle
  //
  // The control logic guarantees that a bank is not read and written in the
  // same cycle. Reads happen only from full banks; writes happen only into
  // the active non-full bank.
  // --------------------------------------------------------------------------
  assign bank_shift_en[0] =
      (do_write && (wr_bank_r == 1'b0)) ||
      (do_read  && (rd_bank_r == 1'b0));

  assign bank_shift_en[1] =
      (do_write && (wr_bank_r == 1'b1)) ||
      (do_read  && (rd_bank_r == 1'b1));

  assign bank_shift_in[0] =
      (do_write && (wr_bank_r == 1'b0)) ? wr_data : bank_shift_out[0];

  assign bank_shift_in[1] =
      (do_write && (wr_bank_r == 1'b1)) ? wr_data : bank_shift_out[1];

  replay_srl_bank #(
      .ELEMENT_WIDTH(ELEMENT_WIDTH),
      .NUM_ELEMENTS (NUM_ELEMENTS)
  ) bank0_i (
      .clk      (clk),
      .shift_en (bank_shift_en[0]),
      .shift_in (bank_shift_in[0]),
      .shift_out(bank_shift_out[0])
  );

  replay_srl_bank #(
      .ELEMENT_WIDTH(ELEMENT_WIDTH),
      .NUM_ELEMENTS (NUM_ELEMENTS)
  ) bank1_i (
      .clk      (clk),
      .shift_en (bank_shift_en[1]),
      .shift_in (bank_shift_in[1]),
      .shift_out(bank_shift_out[1])
  );

  // --------------------------------------------------------------------------
  // Control path
  //
  // wr_idx_r / rd_idx_r are logical positions only.
  // They are not physical memory addresses anymore.
  // --------------------------------------------------------------------------
  always_comb begin
    next_wr_bank      = wr_bank_r;
    next_wr_idx       = wr_idx_r;
    next_rd_bank      = rd_bank_r;
    next_rd_idx       = rd_idx_r;
    next_replay_cycle = replay_cycle_r;
    next_bank_full    = bank_full_r;

    if (do_write) begin
      if (wr_idx_r == LAST_IDX_C) begin
        next_bank_full[wr_bank_r] = 1'b1;
        next_wr_idx               = '0;
        next_wr_bank              = ~wr_bank_r;
      end else begin
        next_wr_idx = wr_idx_r + 1'b1;
      end
    end

    if (do_read) begin
      if (rd_idx_r == LAST_IDX_C) begin
        next_rd_idx = '0;

        if (replay_cycle_r == LAST_CYCLE_C) begin
          next_bank_full[rd_bank_r] = 1'b0;
          next_replay_cycle         = '0;
          next_rd_bank              = ~rd_bank_r;
        end else begin
          next_replay_cycle = replay_cycle_r + 1'b1;
        end
      end else begin
        next_rd_idx = rd_idx_r + 1'b1;
      end
    end
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
    end else begin
      wr_bank_r      <= next_wr_bank;
      wr_idx_r       <= next_wr_idx;
      rd_bank_r      <= next_rd_bank;
      rd_idx_r       <= next_rd_idx;
      replay_cycle_r <= next_replay_cycle;
      bank_full_r    <= next_bank_full;

      if (do_read) begin
        rd_data_r <= bank_shift_out[rd_bank_r];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && do_write && do_read && (wr_bank_r == rd_bank_r)) begin
      $fatal(1, "replay_buffer SRL version does not support same-bank read/write in one cycle");
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