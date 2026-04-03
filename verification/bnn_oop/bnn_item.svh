`ifndef _BNN_ITEM_SVH_
`define _BNN_ITEM_SVH_

class bnn_image_item #(
    int INPUT_DATA_WIDTH = 8
);
    int image_id;
    bit [INPUT_DATA_WIDTH-1:0] pixels[];

    function new();
        image_id = -1;
    endfunction
endclass

// Shared context for a single default end-to-end test run.
//
// Future expansion:
// - Add per-message config objects if you want to randomize ordering or send
//   partial reconfiguration sequences instead of one flat stream.
// - Add phase control fields here if you want tests to inject resets mid-config,
//   mid-image, or mid-output.
class bnn_test_context #(
    int CONFIG_BUS_WIDTH = 64,
    int INPUT_DATA_WIDTH = 8
);
    typedef bit [CONFIG_BUS_WIDTH-1:0]   config_bus_word_t;
    typedef bit [CONFIG_BUS_WIDTH/8-1:0] config_keep_t;

    bnn_fcc_tb_pkg::BNN_FCC_Model #(CONFIG_BUS_WIDTH) model;
    bnn_fcc_tb_pkg::BNN_FCC_Stimulus #(INPUT_DATA_WIDTH) stim;
    bnn_fcc_tb_pkg::LatencyTracker latency;
    bnn_fcc_tb_pkg::ThroughputTracker throughput;

    int actual_topology[];
    int actual_total_layers;
    config_bus_word_t config_bus_data_stream[];
    config_keep_t     config_bus_keep_stream[];
    bnn_image_item #(INPUT_DATA_WIDTH) images[$];
    int num_tests;

    function new();
        actual_total_layers = 0;
        num_tests           = 0;
    endfunction
endclass

`endif
