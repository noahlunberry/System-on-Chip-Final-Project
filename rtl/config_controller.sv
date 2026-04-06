module config_controller #(
    parameter int PARALLEL_INPUTS  = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS    = 256,
    parameter int TOTAL_INPUTS     = 256,
    parameter int LAST_LAYER       = 0,

    // Derived sizing lives here so the port widths stay self-contained.
    localparam int TOTAL_CYCLES     = TOTAL_NEURONS / PARALLEL_NEURONS,
    localparam int W_ADDR_PER_CYCLE = TOTAL_INPUTS / PARALLEL_INPUTS,

    // Each weight RAM stores one full stream for its bank:
    // TOTAL_CYCLES neurons * W_ADDR_PER_CYCLE words per neuron.
    localparam int W_RAM_ADDR_W = $clog2(TOTAL_CYCLES * W_ADDR_PER_CYCLE + 1),

    // Each threshold RAM stores one threshold per neuron-group.
    localparam int T_RAM_ADDR_W = $clog2(TOTAL_CYCLES + 1),

    // Counter widths.
    localparam int TOTAL_CYCLES_W = (TOTAL_CYCLES > 1) ? $clog2(TOTAL_CYCLES + 1) : 1,
    localparam int W_WORD_COUNT_W = (W_ADDR_PER_CYCLE > 1) ? $clog2(W_ADDR_PER_CYCLE) : 1
) (
    input logic clk,
    input logic rst,
    input logic weight_wr_en,
    input logic threshold_wr_en,

    output logic [PARALLEL_NEURONS-1:0] ram_weight_wr_en,
    output logic [PARALLEL_NEURONS-1:0] ram_threshold_wr_en,
    output logic [    W_RAM_ADDR_W-1:0] weight_addr_out    [PARALLEL_NEURONS],
    output logic [    T_RAM_ADDR_W-1:0] threshold_addr_out [PARALLEL_NEURONS],
    output logic                        done
);

  initial begin
    if (TOTAL_NEURONS % PARALLEL_NEURONS)
      $fatal(1, "config_controller requires TOTAL_NEURONS to be divisible by PARALLEL_NEURONS");
    if (TOTAL_INPUTS % PARALLEL_INPUTS)
      $fatal(1, "config_controller requires TOTAL_INPUTS to be divisible by PARALLEL_INPUTS");
  end

  localparam logic [PARALLEL_NEURONS-1:0] ONEHOT0 = {{(PARALLEL_NEURONS - 1) {1'b0}}, 1'b1};

  typedef enum logic [0:0] {
    CONFIGURE,
    DONE
  } state_t;

  // State
  state_t state_r, next_state;

  // Weight datapath registers
  logic [W_WORD_COUNT_W-1:0] w_word_count_r, next_w_word_count;
  logic [PARALLEL_NEURONS-1:0] w_neuron_r, next_w_neuron;
  logic [TOTAL_CYCLES_W-1:0] w_total_cycles_r, next_w_total_cycles;
  logic [W_RAM_ADDR_W-1:0] w_bank_addr_r   [PARALLEL_NEURONS];
  logic [W_RAM_ADDR_W-1:0] next_w_bank_addr[PARALLEL_NEURONS];

  // Threshold datapath registers
  logic [PARALLEL_NEURONS-1:0] t_neuron_r, next_t_neuron;
  logic [TOTAL_CYCLES_W-1:0] t_total_cycles_r, next_t_total_cycles;
  logic [T_RAM_ADDR_W-1:0] t_bank_addr_r   [PARALLEL_NEURONS];
  logic [T_RAM_ADDR_W-1:0] next_t_bank_addr[PARALLEL_NEURONS];

  always_ff @(posedge clk) begin
    if (rst) begin
      state_r          <= CONFIGURE;

      w_word_count_r   <= '0;
      w_neuron_r       <= ONEHOT0;
      w_total_cycles_r <= '0;

      t_neuron_r       <= ONEHOT0;
      t_total_cycles_r <= '0;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        w_bank_addr_r[i] <= '0;
        t_bank_addr_r[i] <= '0;
      end
    end else begin
      state_r          <= next_state;

      w_word_count_r   <= next_w_word_count;
      w_neuron_r       <= next_w_neuron;
      w_total_cycles_r <= next_w_total_cycles;

      t_neuron_r       <= next_t_neuron;
      t_total_cycles_r <= next_t_total_cycles;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        w_bank_addr_r[i] <= next_w_bank_addr[i];
        t_bank_addr_r[i] <= next_t_bank_addr[i];
      end
    end
  end

  always_comb begin
    // Defaults
    next_state          = state_r;

    next_w_word_count   = w_word_count_r;
    next_w_neuron       = w_neuron_r;
    next_w_total_cycles = w_total_cycles_r;

    next_t_neuron       = t_neuron_r;
    next_t_total_cycles = t_total_cycles_r;

    ram_weight_wr_en    = '0;
    ram_threshold_wr_en = '0;

    for (int i = 0; i < PARALLEL_NEURONS; i++) begin
      weight_addr_out[i]    = w_bank_addr_r[i];
      threshold_addr_out[i] = t_bank_addr_r[i];
      next_w_bank_addr[i]   = w_bank_addr_r[i];
      next_t_bank_addr[i]   = t_bank_addr_r[i];
    end

    done = 1'b0;

    case (state_r)
      CONFIGURE: begin
        // weights and thresholds are mutually exclusive
        if (weight_wr_en) begin
          ram_weight_wr_en = w_neuron_r;

          // increment active weight bank address
          for (int i = 0; i < PARALLEL_NEURONS; i++) begin
            if (w_neuron_r[i]) begin
              next_w_bank_addr[i] = w_bank_addr_r[i] + 1'b1;
            end
          end

          // rotate bank after finishing one neuron's word stream
          if (w_word_count_r == W_ADDR_PER_CYCLE - 1) begin
            next_w_word_count = '0;

            if (w_neuron_r[PARALLEL_NEURONS-1]) begin
              next_w_neuron       = ONEHOT0;
              next_w_total_cycles = w_total_cycles_r + 1'b1;
            end else begin
              next_w_neuron = w_neuron_r << 1;
            end
          end else begin
            next_w_word_count = w_word_count_r + 1'b1;
          end
        end else if (threshold_wr_en) begin
          ram_threshold_wr_en = t_neuron_r;

          // increment active threshold bank address
          for (int i = 0; i < PARALLEL_NEURONS; i++) begin
            if (t_neuron_r[i]) begin
              next_t_bank_addr[i] = t_bank_addr_r[i] + 1'b1;
            end
          end

          // rotate threshold bank every write
          if (t_neuron_r[PARALLEL_NEURONS-1]) begin
            next_t_neuron       = ONEHOT0;
            next_t_total_cycles = t_total_cycles_r + 1'b1;
          end else begin
            next_t_neuron = t_neuron_r << 1;
          end
        end

        // move to DONE once everything required is configured
        if (LAST_LAYER) begin
          if (next_w_total_cycles == TOTAL_CYCLES) begin
            next_state = DONE;
          end
        end else begin
          if ((next_w_total_cycles == TOTAL_CYCLES) && (next_t_total_cycles == TOTAL_CYCLES)) begin
            next_state = DONE;
          end
        end
      end

      DONE: begin
        done = 1'b1;

        // Start a new WEIGHT configuration and consume the first write immediately.
        if (weight_wr_en) begin
          done                = 1'b0;
          next_state          = CONFIGURE;

          // Reset weight-side counters
          next_w_word_count   = '0;
          next_w_neuron       = ONEHOT0;
          next_w_total_cycles = '0;

          for (int i = 0; i < PARALLEL_NEURONS; i++) begin
            next_w_bank_addr[i] = '0;
            weight_addr_out[i]  = '0;
          end

          // Consume first weight word right now
          ram_weight_wr_en    = ONEHOT0;
          next_w_bank_addr[0] = 'd1;

          if (W_ADDR_PER_CYCLE == 1) begin
            next_w_word_count = '0;

            if (PARALLEL_NEURONS == 1) begin
              next_w_neuron       = ONEHOT0;
              next_w_total_cycles = 'd1;
            end else begin
              next_w_neuron = ONEHOT0 << 1;
            end
          end else begin
            next_w_word_count = 'd1;
          end
        end  // Start a new THRESHOLD configuration and consume the first write immediately.
        else if (threshold_wr_en) begin
          done                = 1'b0;
          next_state          = CONFIGURE;

          // Reset threshold-side counters
          next_t_neuron       = ONEHOT0;
          next_t_total_cycles = '0;

          for (int i = 0; i < PARALLEL_NEURONS; i++) begin
            next_t_bank_addr[i]   = '0;
            threshold_addr_out[i] = '0;
          end

          // Consume first threshold word right now
          ram_threshold_wr_en = ONEHOT0;
          next_t_bank_addr[0] = 'd1;

          if (PARALLEL_NEURONS == 1) begin
            next_t_neuron       = ONEHOT0;
            next_t_total_cycles = 'd1;
          end else begin
            next_t_neuron = ONEHOT0 << 1;
          end
        end
      end
    endcase
  end

endmodule
