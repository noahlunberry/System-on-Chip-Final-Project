// Greg Stitt
// University of Florida
//
// This file provides the shared base test used by the UVM test variants.

`ifndef _BNN_FCC_BASE_TESTS_SVH_
`define _BNN_FCC_BASE_TESTS_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;


// -----------------------------------------------------------------------------
// Base Test
// -----------------------------------------------------------------------------
// Creates the environment, owns the shared reference model handle used by the
// sequences and scoreboard, and provides common reporting/helpers.
class bnn_fcc_base_test extends uvm_test;
    `uvm_component_utils(bnn_fcc_base_test)

    localparam string MNIST_TEST_VECTOR_INPUT_PATH  = "test_vectors/inputs.hex";
    localparam string MNIST_TEST_VECTOR_OUTPUT_PATH = "test_vectors/expected_outputs.txt";
    localparam string MNIST_MODEL_DATA_PATH         = "model_data";

    bnn_fcc_env env;

    BNN_FCC_Model    #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model;
    BNN_FCC_Stimulus #(bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH) stim;

    int    num_test_images;
    string base_dir;
    bit    verify_model;
    bit    use_custom_topology;
    bit    toggle_data_out_ready;
    bit    debug;

    function new(string name = "bnn_fcc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        string model_path;
        int trained_topology[4];

        super.build_phase(phase);
        env = bnn_fcc_env::type_id::create("env", this);

        if (!uvm_config_db#(int)::get(this, "", "num_test_images", num_test_images))
            `uvm_fatal("NO_NUM_IMAGES", "num_test_images not specified.")

        if (!uvm_config_db#(string)::get(this, "", "base_dir", base_dir))
            `uvm_fatal("NO_BASE_DIR", "base_dir not specified.")

        if (!uvm_config_db#(bit)::get(this, "", "verify_model", verify_model))
            verify_model = 1'b1;

        if (!uvm_config_db#(bit)::get(this, "", "use_custom_topology", use_custom_topology))
            use_custom_topology = 1'b0;

        if (!uvm_config_db#(bit)::get(this, "", "toggle_data_out_ready", toggle_data_out_ready))
            toggle_data_out_ready = 1'b1;

        if (!uvm_config_db#(bit)::get(this, "", "debug", debug))
            debug = 1'b0;

        // The base test is the single owner/publisher of model_h. It either
        // consumes an injected model handle or mirrors the original TB and
        // creates the default trained MNIST model.
        if (!uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "model_h", model)) begin
            if (use_custom_topology) begin
                `uvm_fatal("NO_MODEL",
                           "use_custom_topology=1, but no model_h was provided to the base test.")
            end

            model = new();
            trained_topology = '{784, 256, 256, 10};
            model_path = $sformatf("%s/%s", base_dir, MNIST_MODEL_DATA_PATH);
            model.load_from_file(model_path, trained_topology);
        end

        if (!model.is_loaded)
            `uvm_fatal("MODEL_NOT_LOADED", "Base test received an unloaded model handle.")

        stim = new(model.topology[0]);

        // Publish the one shared model handle to all downstream consumers.
        uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::set(
            uvm_root::get(), "*", "model_h", model
        );
    endfunction

    virtual function void end_of_elaboration();
        // Prints the UVM topology.
        print();
    endfunction

    // Mirrors the optional SV-vs-Python reference-model cross-check in the
    // original non-UVM testbench.
    virtual task verify_reference_model();
        int python_preds[];
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        string input_path;
        string output_path;

        input_path  = $sformatf("%s/%s", base_dir, MNIST_TEST_VECTOR_INPUT_PATH);
        output_path = $sformatf("%s/%s", base_dir, MNIST_TEST_VECTOR_OUTPUT_PATH);

        stim.load_from_file(input_path);
        python_preds = new[stim.get_num_vectors()];
        $readmemh(output_path, python_preds);

        for (int i = 0; i < stim.get_num_vectors(); i++) begin
            int sv_pred;

            stim.get_vector(i, current_img);
            sv_pred = model.compute_reference(current_img);

            if (sv_pred !== python_preds[i]) begin
                `uvm_fatal("MODEL_MISMATCH",
                           $sformatf("SV model says %0d but Python says %0d for image %0d.",
                                     sv_pred, python_preds[i], i))
            end
        end

        `uvm_info(get_type_name(), "SV model successfully verified against Python outputs.", UVM_LOW)
    endtask

    // Replicates the old procedural output-ready logic from bnn_fcc_tb.
    virtual task drive_output_ready();
        env.out_vif.tready <= 1'b1;
        @(posedge env.out_vif.aclk iff env.out_vif.aresetn);

        if (toggle_data_out_ready) begin
            forever begin
                env.out_vif.tready <= $urandom();
                @(posedge env.out_vif.aclk);
            end
        end
        else begin
            forever begin
                env.out_vif.tready <= 1'b1;
                @(posedge env.out_vif.aclk);
            end
        end
    endtask

    // Wait until the scoreboard has observed all expected classifications.
    virtual task wait_for_scoreboard_done();
        wait ((env.scoreboard.passed + env.scoreboard.failed) == num_test_images);
        repeat (5) @(posedge env.in_vif.aclk);
    endtask

    function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        super.report_phase(phase);

        // The report server provides statistics about the simulation.
        svr = uvm_report_server::get_server();

        // If there were any instances of uvm_fatal or uvm_error, then we will
        // consider that to be a failed test.
        if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0) begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST FAILED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end
        else begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST PASSED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end
    endfunction

endclass

`endif
