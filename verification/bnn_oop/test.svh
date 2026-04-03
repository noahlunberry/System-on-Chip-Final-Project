`ifndef _BNN_TEST_SVH_
`define _BNN_TEST_SVH_

`include "environment.svh"
`include "generator.svh"

virtual class base_bnn_test #(
    int CONFIG_BUS_WIDTH  = 64,
    int INPUT_BUS_WIDTH   = 64,
    int INPUT_DATA_WIDTH  = 8,
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
);
    virtual bnn_bfm #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) bfm;

    string name;
    int    use_custom_topology;
    int    actual_topology[];
    int    num_test_images;
    bit    verify_model_en;
    string base_dir;
    bit    toggle_data_out_ready;
    real   config_valid_probability;
    real   data_in_valid_probability;
    realtime clk_period;
    bit    debug;

    bnn_environment #(
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) env_h;

    bnn_generator #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH)
    ) gen_h;

    bnn_test_context #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH)
    ) ctx_h;

    function new(
        virtual bnn_bfm #(
            .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
            .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
            .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
        ) bfm,
        string   name,
        int      use_custom_topology,
        int      actual_topology[],
        int      num_test_images,
        bit      verify_model_en,
        string   base_dir,
        bit      toggle_data_out_ready,
        real     config_valid_probability,
        real     data_in_valid_probability,
        realtime clk_period,
        bit      debug
    );
        this.bfm                       = bfm;
        this.name                      = name;
        this.use_custom_topology       = use_custom_topology;
        this.actual_topology           = new[actual_topology.size()];
        foreach (actual_topology[i]) this.actual_topology[i] = actual_topology[i];
        this.num_test_images           = num_test_images;
        this.verify_model_en           = verify_model_en;
        this.base_dir                  = base_dir;
        this.toggle_data_out_ready     = toggle_data_out_ready;
        this.config_valid_probability  = config_valid_probability;
        this.data_in_valid_probability = data_in_valid_probability;
        this.clk_period                = clk_period;
        this.debug                     = debug;
    endfunction

    virtual function void report_status();
        $display("Results for Test %0s", name);
        env_h.report_status();
    endfunction

    virtual task run();
        $display("Time %0t [Test]: Starting test %0s.", $time, name);

        gen_h.build(ctx_h);
        bfm.reset(5);
        env_h.run(ctx_h);

        if (env_h.get_passed() == ctx_h.num_tests) begin
            $display("[%0t] SUCCESS: all %0d tests completed successfully.",
                     $realtime, ctx_h.num_tests);
        end else begin
            $error("FAILED: %0d out of %0d tests failed.",
                   env_h.get_failed(), ctx_h.num_tests);
        end

        $display("\nStats:");
        $display("Avg latency (cycles) per image: %0.1f cycles", ctx_h.latency.get_avg_cycles());
        $display("Avg latency (time) per image: %0.1f ns", ctx_h.latency.get_avg_time());
        $display("Avg throughput (outputs/sec): %0.1f",
                 ctx_h.throughput.get_outputs_per_sec(ctx_h.num_tests));
        $display("Avg throughput (cycles/output): %0.1f",
                 ctx_h.throughput.get_avg_cycles_per_output(ctx_h.num_tests));

        $display("Time %0t [Test]: Test completed.", $time);
    endtask
endclass

class default_stream_test #(
    int CONFIG_BUS_WIDTH  = 64,
    int INPUT_BUS_WIDTH   = 64,
    int INPUT_DATA_WIDTH  = 8,
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
) extends base_bnn_test #(
    .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
    .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
    .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
    .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
);
    function new(
        virtual bnn_bfm #(
            .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
            .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
            .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
        ) bfm,
        string   name,
        int      use_custom_topology,
        int      actual_topology[],
        int      num_test_images,
        bit      verify_model_en,
        string   base_dir,
        bit      toggle_data_out_ready,
        real     config_valid_probability,
        real     data_in_valid_probability,
        realtime clk_period,
        bit      debug
    );
        super.new(
            bfm,
            name,
            use_custom_topology,
            actual_topology,
            num_test_images,
            verify_model_en,
            base_dir,
            toggle_data_out_ready,
            config_valid_probability,
            data_in_valid_probability,
            clk_period,
            debug
        );

        gen_h = new(
            use_custom_topology,
            actual_topology,
            num_test_images,
            verify_model_en,
            base_dir,
            clk_period,
            debug
        );

        env_h = new(
            bfm,
            config_valid_probability,
            data_in_valid_probability,
            toggle_data_out_ready,
            debug
        );
    endfunction
endclass

`endif
