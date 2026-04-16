module replay_buffer #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128,
    parameter int REUSE_CYCLES  = 1,
    parameter int BUFFER_DEPTH  = NUM_ELEMENTS * 2,
    parameter string RAM_STYLE  = "block"
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

  logic                     wr_bank_r, next_wr_bank;
  logic [INDEX_W-1:0]       wr_idx_r,  next_wr_idx;

  logic                     rd_bank_r, next_rd_bank;
  logic [INDEX_W-1:0]       rd_idx_r,  next_rd_idx;
  logic [CYCLE_W-1:0]       replay_cycle_r, next_replay_cycle;

  logic [1:0]               bank_full_r, next_bank_full;

  logic                     do_write;
  logic                     do_read;

  logic [ELEMENT_WIDTH-1:0] bank_rd_data [0:1];
  logic [1:0]               bank_wr_en;
  logic                     rd_bank_sel_r;
  logic                     rd_bank_sel_rr;

  // Best-timing version: decode status directly from current registered state

  assign rd_ready = bank_full_r[rd_bank_r];
  assign not_full = !bank_full_r[wr_bank_r];
  assign empty    = !(|bank_full_r) && (wr_idx_r == '0);

  assign do_write = wr_en && not_full;
  assign do_read  = rd_en && rd_ready;

  // --------------------------------------------------------------------------
  // RAM bank datapath
  //
  // Fill behavior:
  //   write wr_data into the active write bank at wr_idx_r
  //
  // Replay behavior:
  //   keep both banks reading at rd_idx_r every cycle, then select and
  //   register the requested bank locally.
  //
  // The control logic guarantees that a bank is not read and written in the
  // same cycle. Reads happen only from full banks; writes happen only into
  // the active non-full bank.
  // --------------------------------------------------------------------------
  assign bank_wr_en[0] = do_write && (wr_bank_r == 1'b0);
  assign bank_wr_en[1] = do_write && (wr_bank_r == 1'b1);

  ram_sdp #(
      .DATA_WIDTH (ELEMENT_WIDTH),
      .ADDR_WIDTH (INDEX_W),
      .REG_RD_DATA(1'b1),
      .WRITE_FIRST(1'b0),
      .STYLE      (RAM_STYLE)
  ) bank0_i (
      .clk    (clk),
      .rd_en  (1'b1),
      .rd_addr(rd_idx_r),
      .rd_data(bank_rd_data[0]),
      .wr_en  (bank_wr_en[0]),
      .wr_addr(wr_idx_r),
      .wr_data(wr_data)
  );

  ram_sdp #(
      .DATA_WIDTH (ELEMENT_WIDTH),
      .ADDR_WIDTH (INDEX_W),
      .REG_RD_DATA(1'b1),
      .WRITE_FIRST(1'b0),
      .STYLE      (RAM_STYLE)
  ) bank1_i (
      .clk    (clk),
      .rd_en  (1'b1),
      .rd_addr(rd_idx_r),
      .rd_data(bank_rd_data[1]),
      .wr_en  (bank_wr_en[1]),
      .wr_addr(wr_idx_r),
      .wr_data(wr_data)
  );

  // --------------------------------------------------------------------------
  // Control path
  //
  // wr_idx_r / rd_idx_r are physical addresses within the current bank.
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
      rd_bank_sel_r  <= 1'b0;
      rd_bank_sel_rr <= 1'b0;
      rd_data        <= '0;
    end else begin
      wr_bank_r      <= next_wr_bank;
      wr_idx_r       <= next_wr_idx;
      rd_bank_r      <= next_rd_bank;
      rd_idx_r       <= next_rd_idx;
      replay_cycle_r <= next_replay_cycle;
      bank_full_r    <= next_bank_full;
      rd_bank_sel_rr <= rd_bank_sel_r;
      rd_data        <= bank_rd_data[rd_bank_sel_rr];

      if (do_read) begin
        rd_bank_sel_r <= rd_bank_r;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst && do_write && do_read && (wr_bank_r == rd_bank_r)) begin
      $fatal(1, "replay_buffer assumes reads and writes target different banks");
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
