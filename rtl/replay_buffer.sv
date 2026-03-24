module replay_buffer #(
    parameter int ELEMENT_WIDTH = 16,
    parameter int NUM_ELEMENTS  = 128,
    parameter int REUSE_CYCLES  = 1
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     wr_en,
    input  logic                     rd_en,
    input  logic [ELEMENT_WIDTH-1:0] wr_data,
    output logic [ELEMENT_WIDTH-1:0] rd_data,
    output logic                     empty,
    output logic                     not_full,
    output logic                     full
);

  localparam int COUNT_W = (NUM_ELEMENTS <= 1) ? 1 : $clog2(NUM_ELEMENTS + 1);
  localparam int INDEX_W = (NUM_ELEMENTS <= 1) ? 1 : $clog2(NUM_ELEMENTS);
  localparam int CYCLE_W = (REUSE_CYCLES <= 1) ? 1 : $clog2(REUSE_CYCLES);

  // Ping-Pong Memory Banks
  logic [1:0][NUM_ELEMENTS-1:0][ELEMENT_WIDTH-1:0] d_r, next_d;

  // Bank states: 0 = EMPTY (Ready to write), 1 = FULL (Ready to read)
  logic [1:0] bank_state_r, next_bank_state;
  
  // Pointers
  logic       wr_bank_r, next_wr_bank;
  logic       rd_bank_r, next_rd_bank;

  // Counters
  logic [COUNT_W-1:0] wr_count_r, next_wr_count;
  logic [INDEX_W-1:0] rd_idx_r, next_rd_idx;
  logic [CYCLE_W-1:0] cycle_r, next_cycle;

  logic [ELEMENT_WIDTH-1:0] rd_data_r, next_rd_data;

  // Status flags
  assign not_full = (bank_state_r[wr_bank_r] == 1'b0);
  assign full     = (bank_state_r[rd_bank_r] == 1'b1);
  assign empty    = !full;
  
  assign rd_data  = rd_data_r;

  always_comb begin
    next_d          = d_r;
    next_bank_state = bank_state_r;
    
    next_wr_bank    = wr_bank_r;
    next_wr_count   = wr_count_r;
    
    next_rd_bank    = rd_bank_r;
    next_rd_idx     = rd_idx_r;
    next_cycle      = cycle_r;
    
    next_rd_data    = rd_data_r;

    // --- WRITE PROCESS ---
    if (wr_en && not_full) begin
      next_d[wr_bank_r][wr_count_r] = wr_data;
      
      if (wr_count_r == NUM_ELEMENTS - 1) begin
        next_bank_state[wr_bank_r] = 1'b1; // Mark Bank as FULL
        next_wr_bank  = ~wr_bank_r;        // Toggle Bank
        next_wr_count = '0;
      end else begin
        next_wr_count = wr_count_r + 1'b1;
      end
    end

    // --- READ PROCESS ---
    if (rd_en && full) begin
      next_rd_data = d_r[rd_bank_r][rd_idx_r];

      if (rd_idx_r == NUM_ELEMENTS - 1) begin
        next_rd_idx = '0;

        if (cycle_r == REUSE_CYCLES - 1) begin
          next_bank_state[rd_bank_r] = 1'b0; // Mark Bank as EMPTY
          next_rd_bank = ~rd_bank_r;         // Toggle Bank
          next_cycle   = '0;
        end else begin
          next_cycle = cycle_r + 1'b1;
        end
      end else begin
        next_rd_idx = rd_idx_r + 1'b1;
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      d_r          <= '0;
      bank_state_r <= 2'b00;
      wr_bank_r    <= 1'b0;
      rd_bank_r    <= 1'b0;
      wr_count_r   <= '0;
      rd_idx_r     <= '0;
      cycle_r      <= '0;
      rd_data_r    <= '0;
    end else begin
      d_r          <= next_d;
      bank_state_r <= next_bank_state;
      wr_bank_r    <= next_wr_bank;
      rd_bank_r    <= next_rd_bank;
      wr_count_r   <= next_wr_count;
      rd_idx_r     <= next_rd_idx;
      cycle_r      <= next_cycle;
      rd_data_r    <= next_rd_data;
    end
  end

endmodule
