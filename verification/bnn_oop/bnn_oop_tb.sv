// OOP version of verification/bnn_fcc_tb.sv.
//
// The default_stream_test class intentionally preserves the same phase order and
// randomized behavior as the original monolithic bench:
// 1. Build model/stimulus.
// 2. Reset.
// 3. Stream one flat configuration.
// 4. Stream images.
// 5. Randomly toggle output ready.
// 6. Compare classifications and print the same summary metrics.
//
// Future tests should be added as new classes in test.svh instead of growing the
// default flow in-place.

`timescale 1ns / 100ps

`include "test.svh"

module bnn_oop_tb #(
    parameter int      USE_CUSTOM_TOPOLOGY                      = 1'b0,
    parameter int      CUSTOM_LAYERS                            = 4,
    parameter int      CUSTOM_TOPOLOGY          [CUSTOM_LAYERS] = '{256, 64, 64, 8},
    parameter int      NUM_TEST_IMAGES                          = 50,
    parameter bit      VERIFY_MODEL                             = 1,
    parameter string   BASE_DIR                                 = "/home/UFAD/ruangkanitpawin/Projects/bnn_fcc_contest/python",
    parameter bit      TOGGLE_DATA_OUT_READY                    = 1'b1,
    parameter real     CONFIG_VALID_PROBABILITY                 = 1.0,
    parameter real     DATA_IN_VALID_PROBABILITY                = 0.95,
    parameter realtime TIMEOUT                                  = 100ms,
    parameter realtime CLK_PERIOD                               = 10ns,
    parameter bit      DEBUG                                    = 1'b0,

    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int INPUT_BUS_WIDTH  = 1024,
    parameter int OUTPUT_BUS_WIDTH = 8,

    parameter  int INPUT_DATA_WIDTH  = 8,
    parameter  int OUTPUT_DATA_WIDTH = 4,

    localparam int TRAINED_LAYERS = 4,
    localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10},

    localparam int NON_INPUT_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS - 1 : TRAINED_LAYERS - 1,
    parameter int PARALLEL_INPUTS = 128,
    parameter int PARALLEL_NEURONS[NON_INPUT_LAYERS] = '{256, 64, 10}
);
    localparam int ACTUAL_TOTAL_LAYERS = USE_CUSTOM_TOPOLOGY ? CUSTOM_LAYERS : TRAINED_LAYERS;
    localparam int ACTUAL_TOPOLOGY[ACTUAL_TOTAL_LAYERS] = USE_CUSTOM_TOPOLOGY ? CUSTOM_TOPOLOGY : TRAINED_TOPOLOGY;
    localparam realtime HALF_CLK_PERIOD = CLK_PERIOD / 2.0;

    logic clk = 1'b0;

    bnn_bfm #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) bfm (
        .clk(clk)
    );

    default_stream_test #(
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) test_default = new(
        bfm,
        "Default Stream Test",
        USE_CUSTOM_TOPOLOGY,
        ACTUAL_TOPOLOGY,
        NUM_TEST_IMAGES,
        VERIFY_MODEL,
        BASE_DIR,
        TOGGLE_DATA_OUT_READY,
        CONFIG_VALID_PROBABILITY,
        DATA_IN_VALID_PROBABILITY,
        CLK_PERIOD,
        DEBUG
    );

    initial begin
        assert (INPUT_DATA_WIDTH == 8)
        else $fatal(1, "TB ERROR: INPUT_DATA_WIDTH must be 8. Sub-byte or multi-byte packing logic not yet implemented.");
    end

    bnn_fcc #(
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .TOTAL_LAYERS     (ACTUAL_TOTAL_LAYERS),
        .TOPOLOGY         (ACTUAL_TOPOLOGY),
        .PARALLEL_INPUTS  (PARALLEL_INPUTS),
        .PARALLEL_NEURONS (PARALLEL_NEURONS)
    ) DUT (
        .clk(clk),
        .rst(bfm.rst),

        .config_valid(bfm.config_valid),
        .config_ready(bfm.config_ready),
        .config_data (bfm.config_data),
        .config_keep (bfm.config_keep),
        .config_last (bfm.config_last),

        .data_in_valid(bfm.data_in_valid),
        .data_in_ready(bfm.data_in_ready),
        .data_in_data (bfm.data_in_data),
        .data_in_keep (bfm.data_in_keep),
        .data_in_last (bfm.data_in_last),

        .data_out_valid(bfm.data_out_valid),
        .data_out_ready(bfm.data_out_ready),
        .data_out_data (bfm.data_out_data),
        .data_out_keep (bfm.data_out_keep),
        .data_out_last (bfm.data_out_last)
    );

    initial begin : generate_clock
        forever #HALF_CLK_PERIOD clk <= ~clk;
    end

    initial begin
        $timeformat(-9, 0, " ns", 0);
        test_default.run();
        disable generate_clock;
        disable l_timeout;
    end

    initial begin : l_timeout
        #TIMEOUT;
        $fatal(1, $sformatf("Simulation failed due to timeout of %0t.", TIMEOUT));
    end

endmodule
