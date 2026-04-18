// Adapted from bnn_fcc_tb.sv for pre-configuration layer-level verification.
//
// This testbench does not instantiate rtl/bnn_layer.sv directly because that
// module and the configuration path are still incomplete. Instead, it reuses
// bnn_fcc_tb_pkg to load/generate a model and stimulus, preloads the selected
// layer's weights/thresholds into a local layer harness, then compares the
// layer's output bits against the package reference model.

`timescale 1ns / 100ps

module bnn_layer_manual #(
    parameter int TOTAL_INPUTS     = 8,
    parameter int TOTAL_NEURONS    = 8,
    parameter int PARALLEL_INPUTS  = 8,
    parameter int PARALLEL_NEURONS = 8
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    start,
    input  logic [TOTAL_INPUTS-1:0] data_in,
    output logic                    done,
    output logic [TOTAL_NEURONS-1:0] data_out
);
    localparam int WORDS_PER_NEURON = (TOTAL_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
    localparam int NEURON_BATCHES   = (TOTAL_NEURONS + PARALLEL_NEURONS - 1) / PARALLEL_NEURONS;
    localparam int ACC_WIDTH        = $clog2(TOTAL_INPUTS + 1);
    localparam int WORD_IDX_W       = (WORDS_PER_NEURON > 1) ? $clog2(WORDS_PER_NEURON) : 1;
    localparam int BATCH_IDX_W      = (NEURON_BATCHES > 1) ? $clog2(NEURON_BATCHES) : 1;

    typedef enum logic [1:0] {
        IDLE,
        SEND,
        WAIT_RESULT
    } state_t;

    state_t state_r, next_state;

    logic [WORD_IDX_W-1:0]  word_idx_r, next_word_idx;
    logic [BATCH_IDX_W-1:0] batch_idx_r, next_batch_idx;
    logic                   done_r, next_done;
    logic [TOTAL_NEURONS-1:0] data_out_r, next_data_out;

    logic [PARALLEL_INPUTS-1:0] weight_mem[PARALLEL_NEURONS][NEURON_BATCHES][WORDS_PER_NEURON];
    logic [ACC_WIDTH-1:0]       threshold_mem[PARALLEL_NEURONS][NEURON_BATCHES];

    logic                       np_valid;
    logic                       np_last;
    logic [PARALLEL_INPUTS-1:0] x_chunk;
    logic [PARALLEL_INPUTS-1:0] w_chunk[PARALLEL_NEURONS];
    logic [ACC_WIDTH-1:0]       threshold_chunk[PARALLEL_NEURONS];
    logic                       np_y[PARALLEL_NEURONS];
    logic                       np_y_valid[PARALLEL_NEURONS];

    assign done     = done_r;
    assign data_out = data_out_r;

    always_comb begin
        x_chunk = '0;
        for (int k = 0; k < PARALLEL_INPUTS; k++) begin
            int input_idx;
            input_idx = (int'(word_idx_r) * PARALLEL_INPUTS) + k;
            if (input_idx < TOTAL_INPUTS) x_chunk[k] = data_in[input_idx];
        end

        for (int lane = 0; lane < PARALLEL_NEURONS; lane++) begin
            w_chunk[lane]         = weight_mem[lane][batch_idx_r][word_idx_r];
            threshold_chunk[lane] = threshold_mem[lane][batch_idx_r];
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < PARALLEL_NEURONS; gi++) begin : g_np
            neuron_processor #(
                .P_WIDTH  (PARALLEL_INPUTS),
                .ACC_WIDTH(ACC_WIDTH)
            ) u_np (
                .clk      (clk),
                .rst      (rst),
                .valid_in (np_valid),
                .last     (np_last),
                .x        (x_chunk),
                .w        (w_chunk[gi]),
                .threshold(threshold_chunk[gi]),
                .y        (np_y[gi]),
                .y_valid  (np_y_valid[gi])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        state_r     <= next_state;
        word_idx_r  <= next_word_idx;
        batch_idx_r <= next_batch_idx;
        done_r      <= next_done;
        data_out_r  <= next_data_out;

        if (rst) begin
            state_r     <= IDLE;
            word_idx_r  <= '0;
            batch_idx_r <= '0;
            done_r      <= 1'b0;
            data_out_r  <= '0;
        end
    end

    always_comb begin
        next_state     = state_r;
        next_word_idx  = word_idx_r;
        next_batch_idx = batch_idx_r;
        next_done      = 1'b0;
        next_data_out  = data_out_r;

        np_valid       = 1'b0;
        np_last        = 1'b0;

        case (state_r)
            IDLE: begin
                next_word_idx  = '0;
                next_batch_idx = '0;
                if (start) begin
                    next_data_out = '0;
                    next_state    = SEND;
                end
            end

            SEND: begin
                np_valid = 1'b1;
                np_last  = (word_idx_r == WORDS_PER_NEURON - 1);

                if (np_last) begin
                    next_word_idx = '0;
                    next_state    = WAIT_RESULT;
                end else begin
                    next_word_idx = word_idx_r + 1'b1;
                end
            end

            WAIT_RESULT: begin
                if (np_y_valid[0]) begin
                    for (int lane = 0; lane < PARALLEL_NEURONS; lane++) begin
                        int neuron_idx;
                        neuron_idx = (int'(batch_idx_r) * PARALLEL_NEURONS) + lane;
                        if (neuron_idx < TOTAL_NEURONS) next_data_out[neuron_idx] = np_y[lane];
                    end

                    if (batch_idx_r == NEURON_BATCHES - 1) begin
                        next_done      = 1'b1;
                        next_batch_idx = '0;
                        next_state     = IDLE;
                    end else begin
                        next_batch_idx = batch_idx_r + 1'b1;
                        next_state     = SEND;
                    end
                end
            end

            default: next_state = IDLE;
        endcase
    end

    task automatic clear_model();
        for (int lane = 0; lane < PARALLEL_NEURONS; lane++) begin
            for (int batch = 0; batch < NEURON_BATCHES; batch++) begin
                threshold_mem[lane][batch] = '1;
                for (int word = 0; word < WORDS_PER_NEURON; word++) begin
                    weight_mem[lane][batch][word] = '1;
                end
            end
        end
    endtask

    task automatic load_weight(
        input int lane,
        input int batch,
        input int word,
        input logic [PARALLEL_INPUTS-1:0] value
    );
        if (lane < 0 || lane >= PARALLEL_NEURONS) $fatal(1, "load_weight lane %0d out of range", lane);
        if (batch < 0 || batch >= NEURON_BATCHES) $fatal(1, "load_weight batch %0d out of range", batch);
        if (word < 0 || word >= WORDS_PER_NEURON) $fatal(1, "load_weight word %0d out of range", word);
        weight_mem[lane][batch][word] = value;
    endtask

    task automatic load_threshold(
        input int lane,
        input int batch,
        input logic [ACC_WIDTH-1:0] value
    );
        if (lane < 0 || lane >= PARALLEL_NEURONS) $fatal(1, "load_threshold lane %0d out of range", lane);
        if (batch < 0 || batch >= NEURON_BATCHES) $fatal(1, "load_threshold batch %0d out of range", batch);
        threshold_mem[lane][batch] = value;
    endtask
endmodule

module bnn_layer_preconfig_tb #(
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{8, 8, 8, 8},
    parameter int      TARGET_LAYER                             = 0,
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      VERIFY_MODEL                             = 1,
    parameter string   BASE_DIR                                 = "../python",
    parameter realtime TIMEOUT                                  = 10ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b0,
    parameter int      INPUT_DATA_WIDTH                         = 8,
    parameter int      CONFIG_BUS_WIDTH                         = 64,
    parameter int      PARALLEL_INPUTS                          = 8,
    parameter int      PARALLEL_NEURONS                         = 8
);
    import bnn_fcc_tb_pkg::*;

    localparam int TRAINED_LAYERS = 4;
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10};
    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;
    localparam int LAYER_INPUTS = ACTUAL_TOPOLOGY[TARGET_LAYER];
    localparam int LAYER_NEURONS = ACTUAL_TOPOLOGY[TARGET_LAYER+1];
    localparam int WORDS_PER_NEURON = (LAYER_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
    localparam int ACC_WIDTH = $clog2(LAYER_INPUTS + 1);

    localparam string MNIST_TEST_VECTOR_INPUT_PATH = "test_vectors/inputs.hex";
    localparam string MNIST_TEST_VECTOR_OUTPUT_PATH = "test_vectors/expected_outputs.txt";
    localparam string MNIST_MODEL_DATA_PATH = "model_data";

    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    typedef bit [LAYER_INPUTS-1:0] layer_input_t;
    typedef bit [LAYER_NEURONS-1:0] layer_output_t;
    typedef bit [PARALLEL_INPUTS-1:0] weight_word_t;
    typedef bit [ACC_WIDTH-1:0] threshold_t;

    BNN_FCC_Model #(CONFIG_BUS_WIDTH) model;
    BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim;
    LatencyTracker latency;

    int num_tests;
    int passed;
    int failed;

    logic clk = 1'b0;
    logic rst;
    logic init_done = 1'b0;
    logic layer_start;
    logic layer_done;
    layer_input_t layer_input_bits;
    layer_output_t layer_output_bits;

    bnn_layer_manual #(
        .TOTAL_INPUTS    (LAYER_INPUTS),
        .TOTAL_NEURONS   (LAYER_NEURONS),
        .PARALLEL_INPUTS (PARALLEL_INPUTS),
        .PARALLEL_NEURONS(PARALLEL_NEURONS)
    ) DUT (
        .clk    (clk),
        .rst    (rst),
        .start  (layer_start),
        .data_in(layer_input_bits),
        .done   (layer_done),
        .data_out(layer_output_bits)
    );

    initial begin
        assert (INPUT_DATA_WIDTH == 8)
        else $fatal(1, "TB ERROR: INPUT_DATA_WIDTH must be 8.");
        assert (TARGET_LAYER >= 0 && TARGET_LAYER < ACTUAL_TOTAL_LAYERS - 2)
        else $fatal(1, "TB ERROR: TARGET_LAYER=%0d must select a hidden layer (0 to %0d).", TARGET_LAYER, ACTUAL_TOTAL_LAYERS - 3);
    end

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    task automatic verify_model();
        int python_preds[];
        bit [INPUT_DATA_WIDTH-1:0] current_img[];
        string input_path;
        string output_path;

        input_path  = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_INPUT_PATH);
        output_path = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_OUTPUT_PATH);

        stim.load_from_file(input_path);
        num_tests = stim.get_num_vectors();

        python_preds = new[num_tests];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < num_tests; i++) begin
            int sv_pred;
            stim.get_vector(i, current_img);
            sv_pred = model.compute_reference(current_img);
            if (sv_pred !== python_preds[i]) begin
                $error("TB LOGIC ERROR: Img %0d. SV model says %0d, Python says %0d", i, sv_pred, python_preds[i]);
                $finish;
            end
        end

        $display("SV model successfully verified.");
    endtask

    task automatic build_input_vector(
        input  bit [INPUT_DATA_WIDTH-1:0] img_data[],
        output layer_input_t              result
    );
        result = '0;
        for (int i = 0; i < LAYER_INPUTS; i++) begin
            if (TARGET_LAYER == 0) result[i] = (img_data[i] >= 8'd128);
            else result[i] = bit'(model.get_layer_output(TARGET_LAYER - 1, i));
        end
    endtask

    task automatic build_expected_output(output layer_output_t result);
        result = '0;
        for (int n = 0; n < LAYER_NEURONS; n++) begin
            result[n] = bit'(model.get_layer_output(TARGET_LAYER, n));
        end
    endtask

    task automatic report_mismatch(
        input int            image_idx,
        input layer_output_t expected_bits,
        input layer_output_t actual_bits
    );
        $error("Layer %0d mismatch for image %0d: actual=%0b expected=%0b",
               TARGET_LAYER, image_idx, actual_bits, expected_bits);
        for (int n = 0; n < LAYER_NEURONS; n++) begin
            if (actual_bits[n] !== expected_bits[n]) begin
                $display("  neuron %0d mismatch: actual=%0b expected=%0b",
                         n, actual_bits[n], expected_bits[n]);
            end
        end
    endtask

    task automatic load_dut_from_model();
        DUT.clear_model();

        for (int neuron = 0; neuron < LAYER_NEURONS; neuron++) begin
            int lane;
            int batch;
            threshold_t threshold_word;

            lane = neuron % PARALLEL_NEURONS;
            batch = neuron / PARALLEL_NEURONS;

            threshold_word = threshold_t'(model.threshold[TARGET_LAYER][neuron]);
            DUT.load_threshold(lane, batch, threshold_word);

            for (int word = 0; word < WORDS_PER_NEURON; word++) begin
                weight_word_t packed_weights;

                packed_weights = '1;
                for (int k = 0; k < PARALLEL_INPUTS; k++) begin
                    int input_idx;
                    input_idx = (word * PARALLEL_INPUTS) + k;
                    if (input_idx < LAYER_INPUTS) packed_weights[k] = model.weight[TARGET_LAYER][neuron][input_idx];
                end

                DUT.load_weight(lane, batch, word, packed_weights);
            end
        end
    endtask

    initial begin : l_init_model
        string path;

        model = new();
        stim = new(ACTUAL_TOPOLOGY[0]);
        latency = new(CLK_PERIOD);

        if (!USE_CUSTOM_TOPOLOGY) begin
            $display("--- Loading Trained Model ---");
            path = $sformatf("%s/%s", BASE_DIR, MNIST_MODEL_DATA_PATH);
            model.load_from_file(path, ACTUAL_TOPOLOGY);
            if (VERIFY_MODEL) verify_model();

            $display("--- Loading Test Vectors ---");
            path = $sformatf("%s/%s", BASE_DIR, MNIST_TEST_VECTOR_INPUT_PATH);
            stim.load_from_file(path, NUM_TEST_IMAGES);
        end else begin
            $display("--- Loading Randomized Model ---");
            model.create_random(ACTUAL_TOPOLOGY);

            $display("--- Generating Random Test Vectors ---");
            stim.generate_random_vectors(NUM_TEST_IMAGES);
        end

        num_tests = stim.get_num_vectors();
        load_dut_from_model();

        model.print_summary();
        $display("Testing hidden layer %0d: %0d inputs -> %0d neurons", TARGET_LAYER, LAYER_INPUTS, LAYER_NEURONS);
        $display("Layer harness configuration: PARALLEL_INPUTS=%0d, PARALLEL_NEURONS=%0d", PARALLEL_INPUTS, PARALLEL_NEURONS);

        init_done = 1'b1;
    end

    initial begin : l_driver_and_scoreboard
        bit [INPUT_DATA_WIDTH-1:0] current_img[];
        layer_input_t expected_input_bits;
        layer_output_t expected_output_bits;

        $timeformat(-9, 0, " ns", 0);

        rst             = 1'b1;
        layer_start     = 1'b0;
        layer_input_bits = '0;
        passed          = 0;
        failed          = 0;

        wait (init_done);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        for (int i = 0; i < num_tests; i++) begin
            stim.get_vector(i, current_img);
            void'(model.compute_reference(current_img));

            build_input_vector(current_img, expected_input_bits);
            build_expected_output(expected_output_bits);

            layer_input_bits = expected_input_bits;

            if (DEBUG) begin
                $display("[%0t] Testing image %0d on layer %0d", $realtime, i, TARGET_LAYER);
                model.print_inference_trace();
            end

            latency.start_event(i);
            layer_start = 1'b1;
            @(posedge clk);
            layer_start = 1'b0;

            @(posedge clk iff layer_done);
            latency.end_event(i);

            if (layer_output_bits === expected_output_bits) begin
                passed++;
            end else begin
                failed++;
                report_mismatch(i, expected_output_bits, layer_output_bits);
            end

            @(posedge clk);
        end

        disable generate_clock;
        disable l_timeout;

        if (failed == 0) $display("[%0t] SUCCESS: all %0d layer tests passed.", $realtime, passed);
        else $error("FAILED: %0d out of %0d layer tests failed.", failed, num_tests);

        $display("\nLayer Stats:");
        $display("Avg latency (cycles) per layer eval: %0.1f cycles", latency.get_avg_cycles());
        $display("Avg latency (time) per layer eval: %0.1f ns", latency.get_avg_time());
    end

    initial begin : l_timeout
        #TIMEOUT;
        $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
    end
endmodule
