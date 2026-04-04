module config_controller #(
    parameter int PARALLEL_INPUTS  = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS    = 256,
    parameter int TOTAL_INPUTS     = 256,
    parameter int LAST_LAYER       = 0,

    // Derived sizing lives here so the port widths stay self-contained.
    localparam int TOTAL_CYCLES    = TOTAL_NEURONS / PARALLEL_NEURONS,
    localparam int W_ADDR_PER_CYCLE = TOTAL_INPUTS / PARALLEL_INPUTS,

    // Each weight RAM stores one full stream for its bank:
    // TOTAL_CYCLES neurons * W_ADDR_PER_CYCLE words per neuron.
    localparam int W_RAM_ADDR_W    = $clog2(TOTAL_CYCLES * W_ADDR_PER_CYCLE + 1),

    // Each threshold RAM stores one threshold per neuron-group.
    localparam int T_RAM_ADDR_W    = $clog2(TOTAL_CYCLES + 1),

    // Counter widths.
    localparam int TOTAL_CYCLES_W  = (TOTAL_CYCLES > 1) ? $clog2(TOTAL_CYCLES + 1) : 1,
    localparam int W_WORD_COUNT_W  = (W_ADDR_PER_CYCLE > 1) ? $clog2(W_ADDR_PER_CYCLE) : 1
) (
    input logic clk,
    input logic rst,
    input logic weight_wr_en,
    input logic threshold_wr_en,

    // RAM write interfaces
    // Each RAM now gets its own write address. Only one bank is enabled at a time,
    // but keeping per-bank addresses removes the old global-address add path.
    output logic [PARALLEL_NEURONS-1:0] ram_weight_wr_en,
    output logic [PARALLEL_NEURONS-1:0] ram_threshold_wr_en,
    output logic [W_RAM_ADDR_W-1:0] weight_addr_out[PARALLEL_NEURONS],
    output logic [T_RAM_ADDR_W-1:0] threshold_addr_out[PARALLEL_NEURONS],
    output logic done
);

  // Add assertions to make sure these assumptions are true.
  initial begin
    if (TOTAL_NEURONS % PARALLEL_NEURONS)
      $fatal(1, "config_controller requires TOTAL_NEURONS to be divisible by PARALLEL_NEURONS");
    if (TOTAL_INPUTS % PARALLEL_INPUTS)
      $fatal(1, "config_controller requires TOTAL_INPUTS to be divisible by PARALLEL_INPUTS");
  end

  localparam logic [PARALLEL_NEURONS-1:0] ONEHOT0 =
      {{(PARALLEL_NEURONS - 1){1'b0}}, 1'b1};

  // Registers
  // Weight side:
  // - w_word_count_r tracks which word of the current neuron we are writing.
  // - w_neuron_r is a one-hot bank select.
  // - w_total_cycles_r counts how many full bank sweeps have completed.
  // - w_bank_addr_r[i] is the next weight address for bank i.
  logic [W_WORD_COUNT_W-1:0]         w_word_count_r, next_w_word_count;
  logic [PARALLEL_NEURONS-1:0]       w_neuron_r, next_w_neuron;
  logic [TOTAL_CYCLES_W-1:0]         w_total_cycles_r, next_w_total_cycles;
  logic [W_RAM_ADDR_W-1:0]           w_bank_addr_r[PARALLEL_NEURONS];
  logic [W_RAM_ADDR_W-1:0]           next_w_bank_addr[PARALLEL_NEURONS];

  // Threshold side:
  // Thresholds are simpler because each write is one complete threshold value.
  logic [PARALLEL_NEURONS-1:0]       t_neuron_r, next_t_neuron;
  logic [TOTAL_CYCLES_W-1:0]         t_total_cycles_r, next_t_total_cycles;
  logic [T_RAM_ADDR_W-1:0]           t_bank_addr_r[PARALLEL_NEURONS];
  logic [T_RAM_ADDR_W-1:0]           next_t_bank_addr[PARALLEL_NEURONS];

  // Assignments
  assign ram_weight_wr_en    = {PARALLEL_NEURONS{weight_wr_en}} & w_neuron_r;
  assign ram_threshold_wr_en = {PARALLEL_NEURONS{threshold_wr_en}} & t_neuron_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      w_word_count_r   <= '0;
      w_neuron_r       <= ONEHOT0;  // start at bank 0 to get rid of init state
      w_total_cycles_r <= '0;

      t_neuron_r       <= ONEHOT0;
      t_total_cycles_r <= '0;

      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        w_bank_addr_r[i] <= '0;
        t_bank_addr_r[i] <= '0;
      end
    end else begin
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
    // Default Assignments
    next_w_word_count   = w_word_count_r;
    next_w_neuron       = w_neuron_r;
    next_w_total_cycles = w_total_cycles_r;

    next_t_neuron       = t_neuron_r;
    next_t_total_cycles = t_total_cycles_r;

    // Drive each RAM with its current registered address.
    // This is important: the active bank writes to the current address this cycle,
    // and the incremented address is only used on the next cycle.
    for (int i = 0; i < PARALLEL_NEURONS; i++) begin
      weight_addr_out[i]    = w_bank_addr_r[i];
      threshold_addr_out[i] = t_bank_addr_r[i];
      next_w_bank_addr[i]   = w_bank_addr_r[i];
      next_t_bank_addr[i]   = t_bank_addr_r[i];
    end

    if (weight_wr_en) begin
      // Increment only the active bank's address. All other banks hold.
      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        if (w_neuron_r[i]) begin
          next_w_bank_addr[i] = w_bank_addr_r[i] + 1'b1;
        end
      end

      // If last address for this neuron word-stream, move to word 0 for next bank.
      if (w_word_count_r == W_ADDR_PER_CYCLE - 1) begin
        next_w_word_count = '0;

        // If last neuron bank, move to neuron bank 0.
        if (w_neuron_r[PARALLEL_NEURONS-1] == 1'b1) begin
          next_w_neuron       = ONEHOT0;
          next_w_total_cycles = w_total_cycles_r + 1'b1;
        end else begin
          next_w_neuron = w_neuron_r << 1;  // shift left because this is one-hot enable
        end
      end else begin
        next_w_word_count = w_word_count_r + 1'b1;
      end
    end

    if (threshold_wr_en) begin
      // One threshold write consumes exactly one address in the active bank.
      for (int i = 0; i < PARALLEL_NEURONS; i++) begin
        if (t_neuron_r[i]) begin
          next_t_bank_addr[i] = t_bank_addr_r[i] + 1'b1;
        end
      end

      // Rotate to the next bank every threshold write.
      // If last neuron bank, move to neuron bank 0.
      if (t_neuron_r[PARALLEL_NEURONS-1] == 1'b1) begin
        next_t_neuron       = ONEHOT0;
        next_t_total_cycles = t_total_cycles_r + 1'b1;
      end else begin
        next_t_neuron = t_neuron_r << 1;  // shift left because this is one-hot enable
      end
    end

    // Assert done and enable data-in stream.
    // This stays high after configuration completes until reset.
    done = LAST_LAYER ? (w_total_cycles_r == TOTAL_CYCLES)
                      : (w_total_cycles_r == TOTAL_CYCLES) &&
                        (t_total_cycles_r == TOTAL_CYCLES);
  end
endmodule
