`timescale 1ns / 100ps

module bnn_layer_tb #(
    // DUT configuration
    parameter int MAX_PARALLEL_INPUTS = 8,
    parameter int MAX_INPUTS = 784,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS = 8,
    parameter int TOTAL_NEURONS = 256,
    parameter int TOTAL_INPUTS = 256,
    localparam int W_RAM_ADDR_W = $clog2(
        (TOTAL_NEURONS / PARALLEL_NEURONS) * (TOTAL_INPUTS / PARALLEL_INPUTS) + 1
    ),
    localparam int T_RAM_ADDR_W = $clog2((TOTAL_NEURONS / PARALLEL_NEURONS) + 1),
    localparam int THRESHOLD_DATA_WIDTH = $clog2(MAX_INPUTS + 1),
    localparam int ACC_WIDTH = 1 + $clog2(PARALLEL_INPUTS),

    // Testbench configuration
    parameter int      NUM_TEST_IMAGES           = 10,
    parameter bit      TOGGLE_DATA_OUT_READY     = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY  = 0.8,
    parameter real     DATA_IN_VALID_PROBABILITY = 0.8,
    parameter realtime TIMEOUT                   = 10ms,
    parameter realtime CLK_PERIOD                = 10ns,
    parameter bit      DEBUG                     = 1'b0
);
  import bnn_tb_pkg::*;

  // ─── Derived constants ───────────────────────────────────────────────
  localparam int TOTAL_WEIGHTS = TOTAL_NEURONS * TOTAL_INPUTS;
  localparam int W_ADDR_PER_CYCLE = TOTAL_INPUTS / MAX_PARALLEL_INPUTS;
  localparam int T_ADDR_PER_CYCLE = 1;
  localparam int TOTAL_CYCLES = TOTAL_NEURONS / PARALLEL_NEURONS;
  localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

  // Topology for a single-layer model (input size -> neuron count)
  localparam int LAYER_TOPOLOGY[2] = '{TOTAL_INPUTS, TOTAL_NEURONS};

  // ─── Returns 1 with probability p, 0 with probability 1-p ───────────
  function automatic bit chance(real p);
    if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
    return ($urandom < (p * (2.0 ** 32)));
  endfunction

  // ─── DUT Signals ─────────────────────────────────────────────────────
  logic                            clk = 1'b0;
  logic                            rst;
  logic                            weight_wr_en;
  logic [     PARALLEL_INPUTS-1:0] data_in;
  logic                            valid_in;
  logic                            ready_in;
  logic                            threshold_wr_en;
  logic [ MAX_PARALLEL_INPUTS-1:0] weight_wr_data;
  logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data;
  logic                            valid_out;
  logic [    PARALLEL_NEURONS-1:0] data_out;
  logic [THRESHOLD_DATA_WIDTH-1:0] count_out         [PARALLEL_NEURONS];
  logic                            ready_out;

  // ─── DUT instantiation ──────────────────────────────────────────────
  bnn_layer #(
      .MAX_PARALLEL_INPUTS(MAX_PARALLEL_INPUTS),
      .MAX_INPUTS         (MAX_INPUTS),
      .PARALLEL_INPUTS    (PARALLEL_INPUTS),
      .PARALLEL_NEURONS   (PARALLEL_NEURONS),
      .TOTAL_NEURONS      (TOTAL_NEURONS),
      .TOTAL_INPUTS       (TOTAL_INPUTS)
  ) DUT (
      .clk              (clk),
      .rst              (rst),
      .data_in          (data_in),
      .valid_in         (valid_in),
      .ready_in         (ready_in),
      .weight_wr_en     (weight_wr_en),
      .threshold_wr_en  (threshold_wr_en),
      .weight_wr_data   (weight_wr_data),
      .threshold_wr_data(threshold_wr_data),
      .valid_out        (valid_out),
      .data_out         (data_out),
      .count_out        (count_out),
      .ready_out        (ready_out)
  );

  // ─── Clock generation ───────────────────────────────────────────────
  initial begin : generate_clock
    forever #HALF_CLK_PERIOD clk <= ~clk;
  end

  // ─── Reference model and stimulus ───────────────────────────────────
  BNN_Model #(MAX_PARALLEL_INPUTS, THRESHOLD_DATA_WIDTH) model;
  BNN_FCC_Stimulus #(8) stim;

  typedef bit [MAX_PARALLEL_INPUTS-1:0] weight_data_t;
  typedef weight_data_t weight_data_stream_t[];

  typedef bit [THRESHOLD_DATA_WIDTH-1:0] threshold_data_t;
  typedef threshold_data_t threshold_data_stream_t[];

  weight_data_stream_t    weight_stream;
  threshold_data_stream_t threshold_stream;

  int num_tests;
  int passed;
  int failed;

  // ─── Initialize model ───────────────────────────────────────────────
  initial begin : l_init_model
    model = new();
    stim  = new(TOTAL_INPUTS);

    $display("--- Creating Randomized Single-Layer Model ---");
    model.create_random(LAYER_TOPOLOGY);
    model.print_summary();

    // Get weight and threshold streams for layer 0
    model.get_layer_config(0, 0, weight_stream, threshold_stream);
    // Now get the thresholds separately
    begin
      weight_data_stream_t    dummy_w;
      threshold_data_stream_t t_stream;
      model.get_layer_config(0, 1, dummy_w, t_stream);
      threshold_stream = t_stream;
    end

    $display("--- Weight stream size: %0d words ---", weight_stream.size());
    $display("--- Threshold stream size: %0d words ---", threshold_stream.size());

    // Generate random test input images
    $display("--- Generating %0d Random Test Vectors ---", NUM_TEST_IMAGES);
    stim.generate_random_vectors(NUM_TEST_IMAGES);
    num_tests = stim.get_num_vectors();

    if (DEBUG) model.print_model();
  end

  // ─── Expected output queue ──────────────────────────────────────────
  logic [PARALLEL_NEURONS-1:0] expected_data_out[$];

  // ═══════════════════════════════════════════════════════════════════
  // GOLDEN FUNCTIONS for config_controller address/enable verification
  // ═══════════════════════════════════════════════════════════════════

  // Given the flat weight word index (0, 1, 2, ...), compute expected
  // one-hot write enable and write address that config_controller should produce.
  function automatic void expected_weight_addr(input int flat_idx,
                                               output logic [PARALLEL_NEURONS-1:0] exp_wr_en,
                                               output logic [W_RAM_ADDR_W-1:0] exp_addr);
    int neuron_idx;  // which neuron within the parallel set (0..PARALLEL_NEURONS-1)
    int word_within;  // address within one neuron's BRAM partition
    int total_cycle;  // which full pass through all neurons

    word_within = flat_idx % W_ADDR_PER_CYCLE;
    neuron_idx = (flat_idx / W_ADDR_PER_CYCLE) % PARALLEL_NEURONS;
    total_cycle = flat_idx / (PARALLEL_NEURONS * W_ADDR_PER_CYCLE);

    exp_wr_en = (1 << neuron_idx);
    exp_addr = word_within + (total_cycle * W_ADDR_PER_CYCLE);
  endfunction

  // Given the flat threshold word index, compute expected one-hot enable and address.
  function automatic void expected_threshold_addr(input int flat_idx,
                                                  output logic [PARALLEL_NEURONS-1:0] exp_wr_en,
                                                  output logic [T_RAM_ADDR_W-1:0] exp_addr);
    int neuron_idx;
    int word_within;
    int total_cycle;

    word_within = flat_idx % T_ADDR_PER_CYCLE;
    neuron_idx = (flat_idx / T_ADDR_PER_CYCLE) % PARALLEL_NEURONS;
    total_cycle = flat_idx / (PARALLEL_NEURONS * T_ADDR_PER_CYCLE);

    exp_wr_en = (1 << neuron_idx);
    exp_addr = word_within + (total_cycle * T_ADDR_PER_CYCLE);
  endfunction

  // ═══════════════════════════════════════════════════════════════════
  // DRIVER: Stream weights, thresholds, then input data
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_sequencer_and_driver
    $timeformat(-9, 0, " ns", 0);

    rst               <= 1'b1;
    weight_wr_en      <= 1'b0;
    threshold_wr_en   <= 1'b0;
    weight_wr_data    <= '0;
    threshold_wr_data <= '0;
    data_in           <= '0;
    valid_in          <= 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    repeat (5) @(posedge clk);

    // ── Stream weights ────────────────────────────────────────────
    $display("[%0t] Streaming %0d weight words.", $realtime, weight_stream.size());
    for (int i = 0; i < weight_stream.size(); i++) begin
      // Simulate random gaps on the configuration bus
      while (!chance(
          CONFIG_VALID_PROBABILITY
      )) begin
        weight_wr_en <= 1'b0;
        @(posedge clk);
      end

      weight_wr_en   <= 1'b1;
      weight_wr_data <= weight_stream[i];
      @(posedge clk);
    end
    weight_wr_en <= 1'b0;

    // ── Stream thresholds ─────────────────────────────────────────
    $display("[%0t] Streaming %0d threshold words.", $realtime, threshold_stream.size());
    for (int i = 0; i < threshold_stream.size(); i++) begin
      while (!chance(
          CONFIG_VALID_PROBABILITY
      )) begin
        threshold_wr_en <= 1'b0;
        @(posedge clk);
      end

      threshold_wr_en   <= 1'b1;
      threshold_wr_data <= threshold_stream[i];
      @(posedge clk);
    end
    threshold_wr_en <= 1'b0;

    // ── Wait for configuration to complete ────────────────────────
    $display("[%0t] Configuration streaming done. Waiting for config_done...", $realtime);
    wait (ready_in);
    repeat (5) @(posedge clk);

    // ── Stream input images ───────────────────────────────────────
    for (int img = 0; img < num_tests; img++) begin
      bit [7:0] current_img[];
      logic [PARALLEL_NEURONS-1:0] expected_per_neuron;

      stim.get_vector(img, current_img);

      // Compute expected output for this image
      void'(model.compute_reference(current_img));

      // Build expected output vector from per-neuron layer outputs
      for (int n = 0; n < PARALLEL_NEURONS; n++) begin
        // For a single hidden layer, output is the activation bit
        expected_per_neuron[n] = model.layer_outputs[0][n][0];
      end
      expected_data_out.push_back(expected_per_neuron);

      $display("[%0t] Streaming image %0d (expected output: %b).", $realtime, img, expected_per_neuron);
      if (DEBUG) model.print_inference_trace();

      // Stream the image PARALLEL_INPUTS bits at a time
      for (int j = 0; j < TOTAL_INPUTS; j += PARALLEL_INPUTS) begin
        // Pack PARALLEL_INPUTS bits from the binarized image
        for (int k = 0; k < PARALLEL_INPUTS; k++) begin
          if (j + k < current_img.size()) data_in[k] <= (current_img[j+k] >= 8'd128) ? 1'b1 : 1'b0;
          else data_in[k] <= 1'b0;
        end

        // Simulate random gaps on data_in bus
        while (!chance(
            DATA_IN_VALID_PROBABILITY
        )) begin
          valid_in <= 1'b0;
          @(posedge clk iff ready_in);
        end

        valid_in <= 1'b1;
        @(posedge clk iff ready_in);
      end

      valid_in <= 1'b0;
      @(posedge clk);
    end

    $display("[%0t] All images loaded, waiting for outputs.", $realtime);
    wait (expected_data_out.size() == 0);
    repeat (5) @(posedge clk);

    disable generate_clock;
    disable l_timeout;
    if (passed == num_tests)
      $display("[%0t] SUCCESS: all %0d tests completed successfully.", $realtime, num_tests);
    else $error("FAILED: %0d out of %0d tests failed.", failed, num_tests);
  end

  // ═══════════════════════════════════════════════════════════════════
  // CONFIG ADDRESS MONITOR: verify weight BRAM addresses and enables
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_weight_config_monitor
    logic [PARALLEL_NEURONS-1:0] exp_neuron;
    int exp_addr;
    int exp_total_cycles;
    int exp_addr_out;

    @(negedge rst);

    exp_neuron       = '0;
    exp_neuron[0]    = 1'b1;
    exp_addr         = 0;
    exp_total_cycles = 0;

    forever begin
      @(posedge clk);

      // FIX: Gate the monitor with the master enable, as the one-hot neuron vector is never zero.
      if (weight_wr_en) begin
        exp_addr_out = exp_addr + exp_total_cycles * W_ADDR_PER_CYCLE;

        assert (DUT.u_cfc.ram_weight_wr_en == exp_neuron)
        else
          $error(
              "[Weight Monitor] enable mismatch. expected=%b got=%b", exp_neuron, DUT.u_cfc.ram_weight_wr_en
          );

        assert (DUT.u_cfc.weight_addr_out == exp_addr_out)
        else
          $error(
              "[Weight Monitor] addr mismatch. expected=%0d got=%0d (local=%0d total_cycles=%0d)",
              exp_addr_out,
              DUT.u_cfc.weight_addr_out,
              exp_addr,
              exp_total_cycles
          );

        // advance expected state exactly like DUT
        if (exp_addr == W_ADDR_PER_CYCLE - 1) begin
          exp_addr = 0;
          if (exp_neuron[PARALLEL_NEURONS-1]) begin
            exp_neuron = '0;
            exp_neuron[0] = 1'b1;
            exp_total_cycles++;
          end else begin
            exp_neuron = exp_neuron << 1;
          end
        end else begin
          exp_addr++;
        end
      end
    end
  end

  // ═══════════════════════════════════════════════════════════════════
  // CONFIG ADDRESS MONITOR: verify threshold BRAM addresses and enables
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_threshold_config_monitor
    logic [PARALLEL_NEURONS-1:0] exp_neuron;
    int exp_addr;
    int exp_total_cycles;
    int exp_addr_out;

    @(negedge rst);

    exp_neuron       = '0;
    exp_neuron[0]    = 1'b1;
    exp_addr         = 0;
    exp_total_cycles = 0;

    forever begin
      @(posedge clk);

      // FIX: Gate the monitor with the master enable
      if (threshold_wr_en) begin
        exp_addr_out = exp_addr + exp_total_cycles * T_ADDR_PER_CYCLE;

        assert (DUT.u_cfc.ram_threshold_wr_en == exp_neuron)
        else
          $error(
              "[Threshold Monitor] enable mismatch. expected=%b got=%b",
              exp_neuron,
              DUT.u_cfc.ram_threshold_wr_en
          );

        assert (DUT.u_cfc.threshold_addr_out == exp_addr_out)
        else
          $error(
              "[Threshold Monitor] addr mismatch. expected=%0d got=%0d (local=%0d total_cycles=%0d)",
              exp_addr_out,
              DUT.u_cfc.threshold_addr_out,
              exp_addr,
              exp_total_cycles
          );

        // advance expected state exactly like DUT
        if (exp_addr == T_ADDR_PER_CYCLE - 1) begin
          exp_addr = 0;
          if (exp_neuron[PARALLEL_NEURONS-1]) begin
            exp_neuron = '0;
            exp_neuron[0] = 1'b1;
            exp_total_cycles++;
          end else begin
            exp_neuron = exp_neuron << 1;
          end
        end else begin
          exp_addr++;
        end
      end
    end
  end

  // ═══════════════════════════════════════════════════════════════════
  // OUTPUT MONITOR: verify DUT neuron outputs against reference model
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_output_monitor
    automatic int output_count = 0;
    forever begin
      @(posedge clk iff valid_out && ready_out);
      assert (expected_data_out.size() > 0)
      else $fatal(1, "[Output Monitor] Unexpected output: no expected data in queue.");

      assert (data_out == expected_data_out[0]) begin
        passed++;
        $display("[%0t] Output %0d PASSED: data_out=%b", $realtime, output_count, data_out);
      end else begin
        $error("[Output Monitor] Output %0d FAILED: actual=%b, expected=%b", output_count, data_out,
               expected_data_out[0]);
        failed++;
      end

      void'(expected_data_out.pop_front());
      output_count++;
    end
  end

  // ═══════════════════════════════════════════════════════════════════
  // BACK-PRESSURE: randomly toggle ready_out to exercise flow control
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_toggle_ready
    ready_out <= 1'b1;
    @(posedge clk iff !rst);
    if (TOGGLE_DATA_OUT_READY) begin
      forever begin
        ready_out <= $urandom();
        @(posedge clk);
      end
    end else ready_out <= 1'b1;
  end

  // ═══════════════════════════════════════════════════════════════════
  // TIMEOUT
  // ═══════════════════════════════════════════════════════════════════
  initial begin : l_timeout
    #TIMEOUT;
    $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
  end

endmodule
