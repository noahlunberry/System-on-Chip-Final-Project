module neuron_controller #(
    parameter int PARALLEL_INPUTS  = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_INPUTS     = 32,
    parameter int TOTAL_NEURONS    = 32,
    parameter int W_RAM_ADDR_W     = 12,
    parameter int T_RAM_ADDR_W     = 8,
    parameter int RAM_RD_LATENCY   = 2
) (
    input logic clk,
    input logic rst,
    input logic go,
    input logic valid_data, // enable when the input is valid(buffer not empty)

    // Control signals to Neuron Processors
    output logic valid_in,
    output logic last,
    output logic layer_done,

    // BRAM Read Interface
    output logic                    weight_rd_en,
    output logic [W_RAM_ADDR_W-1:0] weight_rd_addr,
    output logic                    threshold_rd_en,
    output logic [T_RAM_ADDR_W-1:0] threshold_rd_addr
);

  // Constants
  localparam int WORDS_PER_NEURON = TOTAL_INPUTS / PARALLEL_INPUTS;
  localparam int NEURON_BATCHES = TOTAL_NEURONS / PARALLEL_NEURONS;
  typedef enum logic [1:0] {
    START,
    RUN
  } state_t;
  state_t state_r, next_state;

  // Counters
  logic [$clog2(WORDS_PER_NEURON)-1:0] word_count_r, next_word_count;
  logic [$clog2(NEURON_BATCHES)-1:0] batch_count_r, next_batch_count;
  logic [W_RAM_ADDR_W-1:0] addr_count_r, next_addr_count;

  // Registered Outputs
  logic delay_valid_r;
  logic delay_last_r;
  logic delay_layer_done_r;

  assign weight_rd_addr    = addr_count_r;
  assign threshold_rd_addr = batch_count_r;

  // delay valid in and last signals
  delay #(
      .CYCLES(RAM_RD_LATENCY),
      .WIDTH (1)
  ) u_valid_delay (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (delay_valid_r),
      .out(valid_in)
  );

  delay #(
      .CYCLES(RAM_RD_LATENCY),
      .WIDTH (1)
  ) u_last_delay (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (delay_last_r),
      .out(last)
  );

  delay #(
      .CYCLES(RAM_RD_LATENCY),
      .WIDTH (1)
  ) u_last_layer (
      .clk(clk),
      .rst(rst),
      .en (1'b1),
      .in (delay_layer_done_r),
      .out(layer_done)
  );

  always_ff @(posedge clk) begin
    state_r       <= next_state;
    word_count_r  <= next_word_count;
    batch_count_r <= next_batch_count;
    addr_count_r  <= next_addr_count;

    if (rst) begin
      state_r       <= START;
      word_count_r  <= '0;
      batch_count_r <= '0;
      addr_count_r  <= '0;
    end
  end

  always_comb begin
    // Defaults
    next_state         = state_r;
    next_word_count    = word_count_r;
    next_batch_count   = batch_count_r;
    next_addr_count    = addr_count_r;

    weight_rd_en       = 1'b0;
    threshold_rd_en    = 1'b0;
    delay_valid_r      = 1'b0;
    delay_last_r       = 1'b0;
    delay_layer_done_r = 1'b0;

    case (state_r)
      START: begin
        next_word_count  = '0;
        next_batch_count = '0;
        next_addr_count  = '0;
        if (go) next_state = RUN;
      end

      RUN: begin
        if (valid_data) begin
          weight_rd_en    = 1'b1;
          threshold_rd_en = 1'b1;
          // valid in is delayed 1 cycle after the weight/threshold rd en's
          delay_valid_r   = 1'b1;

          // Address always increments to pull next weight/input chunk unless only one batch
          next_addr_count = addr_count_r + 1'b1;

          // Check if this is the last input for the current neuron set
          if (word_count_r == WORDS_PER_NEURON - 1) begin
            delay_last_r    = 1'b1;
            next_word_count = '0;

            // Check if we've done all neuron batches, if so set next address count to 0
            if (batch_count_r == NEURON_BATCHES - 1) begin
              delay_layer_done_r = 1'b1;
              next_word_count = '0;
              next_batch_count = '0;
              next_addr_count = '0;
            end else begin
              next_batch_count = batch_count_r + 1'b1;
            end
          end else begin
            next_word_count = word_count_r + 1'b1;
          end
        end
      end

      default: next_state = START;
    endcase
  end

endmodule
