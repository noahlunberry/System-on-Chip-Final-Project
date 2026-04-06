// Used to specify the parameter configuration for the DUT
package bnn_fcc_uvm_pkg;

// Bus configuratio
    parameter int CONFIG_BUS_WIDTH = 64;
    parameter int INPUT_BUS_WIDTH  = 1024;
    parameter int OUTPUT_BUS_WIDTH = 8;

    // App configuration
    parameter  int INPUT_DATA_WIDTH  = 8;
    // localparam int INPUTS_PER_CYCLE  = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;
    // localparam int BYTES_PER_INPUT   = INPUT_DATA_WIDTH / 8;
    parameter  int OUTPUT_DATA_WIDTH = 4;

    // Should not be changed
    //localparam int TRAINED_LAYERS = 4;
    //localparam int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10};
    parameter int TRAINED_LAYERS = 4;
    parameter int TRAINED_TOPOLOGY[TRAINED_LAYERS] = '{784, 256, 256, 10};

    // DUT configuration (can be modified or extended for your own DUT)        
    parameter int PARALLEL_INPUTS = 128;
    parameter int PARALLEL_NEURONS[TRAINED_LAYERS-1] = '{256, 64, 10};

    // These enums let tests, coverage, and helper code exchange descriptive
    // reconfiguration/reset states without relying on ad-hoc integer literals.
    typedef enum int {
        BNN_CFG_ORDER_LAYER_INTERLEAVED = 0,
        BNN_CFG_ORDER_WEIGHTS_THEN_THRESH = 1,
        BNN_CFG_ORDER_THRESH_THEN_WEIGHTS = 2
    } bnn_cfg_order_e;

    typedef enum int {
        BNN_RECONFIG_FULL = 0,
        BNN_RECONFIG_WEIGHTS_ONLY = 1,
        BNN_RECONFIG_THRESH_ONLY = 2,
        BNN_RECONFIG_PARTIAL = 3
    } bnn_reconfig_kind_e;

    // Used by system-level coverage to bucket resets by when they occurred.
    typedef enum int {
        BNN_RESET_IDLE = 0,
        BNN_RESET_DURING_CONFIG = 1,
        BNN_RESET_DURING_IMAGE = 2,
        BNN_RESET_DURING_OUTPUT = 3,
        BNN_RESET_AT_TLAST = 4
    } bnn_reset_phase_e;

    // Carries the original TB's custom-topology parameters into the UVM
    // test layer, where the shared model handle is created.
    class bnn_fcc_topology_cfg;
        int custom_layers;
        int custom_topology[];

        function new();
            custom_layers = 0;
            custom_topology = new[0];
        endfunction
    endclass

  import axi4_stream_pkg::*;

endpackage
