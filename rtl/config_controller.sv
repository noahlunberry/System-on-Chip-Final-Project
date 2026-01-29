module config_controller #(
    parameter int MANAGER_BUS_WIDTH = 8,
    parameter int PARALLEL_NEURONS  = 8,
    parameter int PARALLEL_INPUTS   = 8,   // MANAGER BUS WIDTH MUST MATCH PARALLEL INPUTS
    parameter int W_RAM_DATA_W      = 32,
    parameter int W_RAM_ADDR_W      = 10,
    parameter int T_RAM_ADDR_W      = 10
) (
    input logic clk,
    input logic rst,

    // Config stream interface
    input  logic        config_rd_en,
    input  logic        msg_type,          // 0 for weights, 1 for thresholds
    input  logic [15:0] total_bytes,
    input  logic [ 7:0] bytes_per_neuron,
    output logic        payload_done,

    // RAM write interfaces
    output logic                    weight_wr_en   [PARALLEL_NEURONS],
    output logic                    threshold_wr_en[PARALLEL_NEURONS],
    output logic [W_RAM_ADDR_W-1:0] addr_out
);

  localparam int BYTES_PER_BEAT = MANAGER_BUS_WIDTH / 8;
  localparam int GLOBAL_COUNT_W = 16;  // Simplified for clarity, matches total_bytes
  localparam int BATCH_COUNT_W = 8;
  localparam int NEURON_IDX_W = $clog2(PARALLEL_NEURONS);

  typedef enum logic [1:0] {
    START,
    RUN,
    DONE
  } state_t;

  // Registers
  state_t state_r, next_state;
  logic payload_done_r, next_payload_done;
  logic [BATCH_COUNT_W-1:0] batch_count_r, next_batch_count;
  logic [GLOBAL_COUNT_W-1:0] global_count_r, next_global_count;
  logic [NEURON_IDX_W-1:0] neuron_idx_r, next_neuron_idx;
  logic [BATCH_COUNT_W-1:0] beats_per_neuron_r, next_beats_per_neuron;
  logic [GLOBAL_COUNT_W-1:0] total_beats_r, next_total_beats;

  // Pointer Array
  logic [W_RAM_ADDR_W-1:0] addr_pointers_r[PARALLEL_NEURONS];
  logic [W_RAM_ADDR_W-1:0] next_addr_pointers[PARALLEL_NEURONS];

  // Added registers for Write Enables
  logic weight_wr_en_r, next_weight_wr_en[PARALLEL_NEURONS];
  logic threshold_wr_en_r, next_threshold_wr_en[PARALLEL_NEURONS];

  // Assignments
  assign addr_out        = addr_pointers_r[neuron_idx_r];
  assign weight_wr_en    = weight_wr_en_r;
  assign threshold_wr_en = threshold_wr_en_r;

  always_ff @(posedge clk) begin
    state_r            <= next_state;
    batch_count_r      <= next_batch_count;
    global_count_r     <= next_global_count;
    neuron_idx_r       <= next_neuron_idx;
    beats_per_neuron_r <= next_beats_per_neuron;
    total_beats_r      <= next_total_beats;
    addr_pointers_r    <= next_addr_pointers;
    weight_wr_en_r     <= next_weight_wr_en;
    threshold_wr_en_r  <= next_threshold_wr_en;

    if (rst) begin
      state_r <= START;

    end
  end

  always_comb begin
    // Default Assignments
    next_state              = state_r;
    next_batch_count        = batch_count_r;
    next_global_count       = global_count_r;
    next_neuron_idx         = neuron_idx_r;
    next_beats_per_neuron   = beats_per_neuron_r;
    next_total_beats        = total_beats_r;
    next_addr_pointers      = addr_pointers_r;

    next_weight_wr_en[i]    = 1'b0;
    next_threshold_wr_en[i] = 1'b0;

    case (state_r)
      START: begin
        payload_done = 0;
        if (config_rd_en) begin
          next_state            = RUN;
          next_beats_per_neuron = bytes_per_neuron >> $clog2(BYTES_PER_BEAT);
          next_total_beats      = total_bytes >> $clog2(BYTES_PER_BEAT);
        end

        next_batch_count  = '0;
        next_global_count = '0;
        next_neuron_idx   = '0;

        for (int i = 0; i < PARALLEL_NEURONS; i++) begin
          next_addr_pointers[i]   = '0;
          next_weight_wr_en[i]    = '0;
          next_threshold_wr_en[i] = '0;
        end
      end

      RUN: begin
        if (config_rd_en) begin
          if (msg_type == 1'b0) next_weight_wr_en[neuron_idx_r] = 1'b1;
          else next_threshold_wr_en[neuron_idx_r] = 1'b1;

          next_addr_pointers[neuron_idx_r] = addr_pointers_r[neuron_idx_r] + 1'b1;
          next_batch_count                 = batch_count_r + 1'b1;
          next_global_count                = global_count_r + 1'b1;

          if (global_count_r == total_beats_r - 1'b1) begin
            next_state = DONE;
          end else if (batch_count_r == beats_per_neuron_r - 1'b1) begin
            next_batch_count = '0;
            next_neuron_idx  = (neuron_idx_r == PARALLEL_NEURONS - 1) ? '0 : neuron_idx_r + 1'b1;
          end
        end
      end

      DONE: begin
        payload_done = 1;
        if (config_rd_en) begin
          next_state            = RUN;
          next_beats_per_neuron = bytes_per_neuron >> $clog2(BYTES_PER_BEAT);
          next_total_beats      = total_bytes >> $clog2(BYTES_PER_BEAT);
        end

        next_batch_count  = '0;
        next_global_count = '0;
        next_neuron_idx   = '0;

        for (int i = 0; i < PARALLEL_NEURONS; i++) begin
          next_addr_pointers[i]   = '0;
          next_weight_wr_en[i]    = '0;
          next_threshold_wr_en[i] = '0;
        end
      end

      default: next_state = START;
    endcase
  end
endmodule
