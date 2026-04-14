module fifo_vr #(
    parameter int N = 1,  // write width in bits
    parameter int M = 1,  // read width in bits
    parameter int P = 1,  // depth in read words = 2^P
    parameter bit FWFT = 1'b1,  // 1 = show-ahead / FWFT, 0 = registered read data

    // Assert alm_full when this many or fewer writes remain before full.
    parameter int ALM_FULL_THRESH = 1,

    // Assert alm_empty when this many or fewer reads remain in the FIFO.
    parameter int ALM_EMPTY_THRESH = 1
) (
    input logic         clk,
    input logic         rst,
    input logic         rd_en,
    input logic         wr_en,
    input logic [N-1:0] wr_data,

    output logic         alm_full,
    output logic         full,
    output logic         alm_empty,
    output logic         empty,
    output logic [M-1:0] rd_data
);

  // -------------------------------------------------------------------------
  // Derived constants
  // -------------------------------------------------------------------------
  localparam int FIFO_SIZE = (1 << P);  // number of M-bit read words
  localparam int MEM_SIZE = FIFO_SIZE * M;
  localparam int NUM_RD_SLOTS = FIFO_SIZE;
  localparam int NUM_WR_SLOTS = MEM_SIZE / N;

  localparam int RD_ADDR_W = (NUM_RD_SLOTS <= 1) ? 1 : $clog2(NUM_RD_SLOTS);
  localparam int WR_ADDR_W = (NUM_WR_SLOTS <= 1) ? 1 : $clog2(NUM_WR_SLOTS);
  localparam int FILL_W = (MEM_SIZE <= 1) ? 1 : $clog2(MEM_SIZE + 1);

  // Thresholds converted into bit counts once at elaboration time.
  localparam int ALM_EMPTY_LIMIT = ALM_EMPTY_THRESH * M;
  localparam int ALM_FULL_LIMIT = MEM_SIZE - (ALM_FULL_THRESH * N);

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------
  logic [WR_ADDR_W-1:0] wraddr;
  logic [RD_ADDR_W-1:0] rdaddr;

  logic [MEM_SIZE-1:0] mem;
  logic [M-1:0] rd_data_r;
  logic [FILL_W-1:0] fill;

  // -------------------------------------------------------------------------
  // Control / next-state
  // -------------------------------------------------------------------------
  logic do_write, do_read;

  logic [FILL_W-1:0] fill_next;
  logic empty_next, full_next;
  logic alm_empty_next, alm_full_next;

  logic [FILL_W:0] fill_next_plus_n;

  assign do_write = wr_en && !full;
  assign do_read  = rd_en && !empty;

  always_comb begin
    unique case ({
      do_write, do_read
    })
      2'b10:   fill_next = fill + N;
      2'b01:   fill_next = fill - M;
      2'b11:   fill_next = fill + N - M;
      default: fill_next = fill;
    endcase
  end

  assign fill_next_plus_n = {1'b0, fill_next} + N;

  assign empty_next       = (fill_next < M);
  assign full_next        = (fill_next_plus_n > MEM_SIZE);
  assign alm_empty_next   = (fill_next <= ALM_EMPTY_LIMIT);
  assign alm_full_next    = (fill_next >= ALM_FULL_LIMIT);

  // -------------------------------------------------------------------------
  // Memory write
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst && do_write) begin
      for (int i = 0; i < N; i++) begin
        mem[wraddr*N+i] <= wr_data[i];
      end
    end
  end

  // -------------------------------------------------------------------------
  // Read data output
  // -------------------------------------------------------------------------
  generate
    if (FWFT) begin : g_fwft
      for (genvar j = 0; j < M; j++) begin
        assign rd_data[j] = (!rst && !empty) ? mem[rdaddr*M+j] : 1'b0;
      end
    end else begin : g_registered_read
      assign rd_data = rd_data_r;
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_data_r <= '0;
    end else if (!FWFT && do_read) begin
      for (int i = 0; i < M; i++) begin
        rd_data_r[i] <= mem[rdaddr*M+i];
      end
    end
  end

  // -------------------------------------------------------------------------
  // Write pointer
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      wraddr <= '0;
    end else if (do_write) begin
      if (wraddr == NUM_WR_SLOTS - 1) wraddr <= '0;
      else wraddr <= wraddr + 1'b1;
    end
  end

  // -------------------------------------------------------------------------
  // Read pointer
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      rdaddr <= '0;
    end else if (do_read) begin
      if (rdaddr == NUM_RD_SLOTS - 1) rdaddr <= '0;
      else rdaddr <= rdaddr + 1'b1;
    end
  end

  // -------------------------------------------------------------------------
  // Fill / flags
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      fill      <= '0;
      full      <= 1'b0;
      empty     <= 1'b1;
      alm_full  <= 1'b0;
      alm_empty <= 1'b1;
    end else begin
      fill      <= fill_next;
      full      <= full_next;
      empty     <= empty_next;
      alm_full  <= alm_full_next;
      alm_empty <= alm_empty_next;
    end
  end

  // -------------------------------------------------------------------------
  // Optional parameter legality checks
  // -------------------------------------------------------------------------
  initial begin
    if (ALM_EMPTY_THRESH < 0 || ALM_EMPTY_THRESH > FIFO_SIZE) begin
      $error("ALM_EMPTY_THRESH must be between 0 and FIFO_SIZE.");
    end
    if (ALM_FULL_THRESH < 0 || ALM_FULL_THRESH > NUM_WR_SLOTS) begin
      $error("ALM_FULL_THRESH must be between 0 and NUM_WR_SLOTS.");
    end
    if ((MEM_SIZE % N) != 0) begin
      $error("MEM_SIZE must be divisible by N.");
    end
  end

endmodule
