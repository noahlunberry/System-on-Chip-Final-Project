`ifndef _BNN_GENERATOR_SVH_
`define _BNN_GENERATOR_SVH_

`include "bnn_item.svh"

class bnn_generator #(
    int CONFIG_BUS_WIDTH = 64,
    int INPUT_DATA_WIDTH = 8
);
    localparam string MNIST_TEST_VECTOR_INPUT_PATH  = "test_vectors/inputs.hex";
    localparam string MNIST_TEST_VECTOR_OUTPUT_PATH = "test_vectors/expected_outputs.txt";
    localparam string MNIST_MODEL_DATA_PATH         = "model_data";

    int      use_custom_topology;
    int      actual_topology[];
    int      num_test_images;
    bit      verify_model_en;
    string   base_dir;
    realtime clk_period;
    bit      debug;

    function new(
        input int      use_custom_topology,
        input int      actual_topology[],
        input int      num_test_images,
        input bit      verify_model_en,
        input string   base_dir,
        input realtime clk_period,
        input bit      debug
    );
        this.use_custom_topology = use_custom_topology;
        this.actual_topology     = new[actual_topology.size()];
        foreach (actual_topology[i]) this.actual_topology[i] = actual_topology[i];
        this.num_test_images     = num_test_images;
        this.verify_model_en     = verify_model_en;
        this.base_dir            = base_dir;
        this.clk_period          = clk_period;
        this.debug               = debug;
    endfunction

    task automatic verify_model(ref bnn_test_context #(CONFIG_BUS_WIDTH, INPUT_DATA_WIDTH) ctx);
        int python_preds[];
        bit [INPUT_DATA_WIDTH-1:0] current_img[];
        string input_path;
        string output_path;

        input_path  = $sformatf("%s/%s", base_dir, MNIST_TEST_VECTOR_INPUT_PATH);
        output_path = $sformatf("%s/%s", base_dir, MNIST_TEST_VECTOR_OUTPUT_PATH);

        ctx.stim.load_from_file(input_path);
        ctx.num_tests = ctx.stim.get_num_vectors();

        python_preds = new[ctx.num_tests];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < ctx.num_tests; i++) begin
            int sv_pred;
            ctx.stim.get_vector(i, current_img);
            sv_pred = ctx.model.compute_reference(current_img);

            if (sv_pred !== python_preds[i]) begin
                $error("TB LOGIC ERROR: Img %0d. SV Model says %0d, Python says %0d",
                       i, sv_pred, python_preds[i]);
                $finish;
            end
        end

        $display("SV model successfully verified.");
    endtask

    task automatic build(ref bnn_test_context #(CONFIG_BUS_WIDTH, INPUT_DATA_WIDTH) ctx);
        string path;

        ctx = new();
        ctx.actual_total_layers = actual_topology.size();
        ctx.actual_topology     = new[actual_topology.size()];
        foreach (actual_topology[i]) ctx.actual_topology[i] = actual_topology[i];
        ctx.model               = new();
        ctx.stim                = new(actual_topology[0]);
        ctx.latency             = new(clk_period);
        ctx.throughput          = new(clk_period);

        if (!use_custom_topology) begin
            $display("--- Loading Trained Model ---");
            path = $sformatf("%s/%s", base_dir, MNIST_MODEL_DATA_PATH);
            ctx.model.load_from_file(path, ctx.actual_topology);
            if (verify_model_en) verify_model(ctx);

            // This intentionally preserves the original bench behavior, which
            // encodes one flat stream and asserts TLAST only on the final beat.
            // Future tests should replace this with a per-message sequence built
            // from model.get_layer_config() so message ordering can vary.
            ctx.model.encode_configuration(ctx.config_bus_data_stream, ctx.config_bus_keep_stream);
            $display("--- Configuration created: %0d words (%0d-bit wide) ---",
                     ctx.config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            $display("--- Loading Test Vectors ---");
            path = $sformatf("%s/%s", base_dir, MNIST_TEST_VECTOR_INPUT_PATH);
            ctx.stim.load_from_file(path, num_test_images);
        end else begin
            $display("--- Loading Randomized Model ---");
            ctx.model.create_random(ctx.actual_topology);
            ctx.model.encode_configuration(ctx.config_bus_data_stream, ctx.config_bus_keep_stream);
            $display("--- Configuration created: %0d words (%0d-bit wide) ---",
                     ctx.config_bus_data_stream.size(), CONFIG_BUS_WIDTH);

            $display("--- Generating Random Test Vectors ---");
            ctx.stim.generate_random_vectors(num_test_images);
        end

        ctx.num_tests = ctx.stim.get_num_vectors();
        ctx.images.delete();

        for (int i = 0; i < ctx.num_tests; i++) begin
            bnn_image_item #(INPUT_DATA_WIDTH) img_item;

            img_item = new();
            img_item.image_id = i;
            ctx.stim.get_vector(i, img_item.pixels);
            ctx.images.push_back(img_item);
        end

        ctx.model.print_summary();
        if (debug) ctx.model.print_model();
    endtask
endclass

`endif
