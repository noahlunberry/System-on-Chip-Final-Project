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

  typedef enum logic {
    WRITE_ST,
    READ_ST
  } state_t;

  state_t state_r, next_state;

  logic [NUM_ELEMENTS-1:0][ELEMENT_WIDTH-1:0] d_r, next_d;

  logic [COUNT_W-1:0] count_r, next_count;
  logic [INDEX_W-1:0] rd_idx_r, next_rd_idx;
  logic [CYCLE_W-1:0] cycle_r, next_cycle;

  logic [ELEMENT_WIDTH-1:0] rd_data_r, next_rd_data;

  logic wr_fire, rd_fire;

  assign rd_data  = rd_data_r;

  assign empty    = (state_r == WRITE_ST);
  assign full     = (state_r == READ_ST);
  assign not_full = (state_r == WRITE_ST) && (count_r < NUM_ELEMENTS);

  assign wr_fire  = (state_r == WRITE_ST) && wr_en && (count_r < NUM_ELEMENTS);
  assign rd_fire  = (state_r == READ_ST) && rd_en;

  always_comb begin
    next_state   = state_r;
    next_d       = d_r;
    next_count   = count_r;
    next_rd_idx  = rd_idx_r;
    next_cycle   = cycle_r;
    next_rd_data = rd_data_r;

    case (state_r)

      WRITE_ST: begin
        // while writing, reads are considered invalid / buffer not ready
        next_rd_data = '0;
        next_rd_idx  = '0;
        next_cycle   = '0;

        if (wr_fire) begin
          next_d[count_r] = wr_data;
          next_count      = count_r + 1'b1;

          // once the frame is full, move into READ state
          if (count_r == NUM_ELEMENTS - 1) begin
            next_state  = READ_ST;
            next_rd_idx = '0;
            next_cycle  = '0;
          end
        end
      end

      READ_ST: begin
        if (rd_fire) begin
          // output current element
          next_rd_data = d_r[rd_idx_r];

          // end of one pass through the buffer
          if (rd_idx_r == NUM_ELEMENTS - 1) begin
            next_rd_idx = '0;

            // done with all requested reuse cycles
            if (cycle_r == REUSE_CYCLES - 1) begin
              next_state = WRITE_ST;
              next_count = '0;
              next_cycle = '0;
              next_rd_idx = '0;

              // clear stored data because you asked to reset data registers
              next_d = '0;

              // note:
              // next_rd_data is left as the final word for this cycle.
              // it will clear on the following WRITE cycle.
            end else begin
              next_cycle = cycle_r + 1'b1;
            end
          end else begin
            next_rd_idx = rd_idx_r + 1'b1;
          end
        end
      end

      default: begin
        next_state   = WRITE_ST;
        next_d       = '0;
        next_count   = '0;
        next_rd_idx  = '0;
        next_cycle   = '0;
        next_rd_data = '0;
      end

    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_r   <= WRITE_ST;
      d_r       <= '0;
      count_r   <= '0;
      rd_idx_r  <= '0;
      cycle_r   <= '0;
      rd_data_r <= '0;
    end else begin
      state_r   <= next_state;
      d_r       <= next_d;
      count_r   <= next_count;
      rd_idx_r  <= next_rd_idx;
      cycle_r   <= next_cycle;
      rd_data_r <= next_rd_data;
    end
  end

endmodule
