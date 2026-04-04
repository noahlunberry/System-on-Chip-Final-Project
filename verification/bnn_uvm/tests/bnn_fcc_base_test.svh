// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// TEST: bnn_fcc_base_test
// Maps to: IMPLEMENTATION_PLAN.md §"Corner-case and stress tests to explicitly implement"
//
// DESCRIPTION:
// Base test providing common setup for all derived tests. Follows filter_base_test.svh
// pattern: build env, configure model/stimulus, provide report_phase with full coverage
// summary printout.
//
// Changes from prior version:
//   - Added coverage handle to config_db so sequences can sample coverage
//   - Added report_phase with per-covergroup coverage summary (filter_base_test pattern)
//   - Added end_of_elaboration_phase topology printout

`ifndef _BNN_FCC_BASE_TEST_SVH_
`define _BNN_FCC_BASE_TEST_SVH_

class bnn_fcc_base_test extends uvm_test;
    `uvm_component_utils(bnn_fcc_base_test)

    bnn_fcc_env env;
    BNN_FCC_Model #(64) model;
    BNN_FCC_Stimulus #(8) stim;
    bnn_expected_queue expected_q;

    int use_custom_topology;
    string base_dir;
    int bnn_topology[];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = bnn_fcc_env::type_id::create("env", this);

        model      = new();
        stim       = new(8);
        expected_q = new();

        // Get top-level configs from config_db (set by bnn_fcc_uvm_tb)
        if (!uvm_config_db#(int)::get(this, "", "use_custom_topology", use_custom_topology))
            use_custom_topology = 0;
        if (!uvm_config_db#(string)::get(this, "", "base_dir", base_dir))
            base_dir = "../python";

        begin
            bnn_fcc_uvm_tb::int_q_wrapper wrap;
            if (uvm_config_db#(bnn_fcc_uvm_tb::int_q_wrapper)::get(this, "", "bnn_topology", wrap))
                bnn_topology = wrap.arr;
        end

        stim = new(bnn_topology[0]);

        // Load or randomize model/stimulus
        if (!use_custom_topology) begin
            string path = $sformatf("%s/model_data", base_dir);
            model.load_from_file(path, bnn_topology);
            path = $sformatf("%s/test_vectors/inputs.hex", base_dir);
            stim.load_from_file(path, 50);
        end else begin
            model.create_random(bnn_topology);
            stim.generate_random_vectors(50);
        end

        // Publish shared objects to config_db for sequences/scoreboard/coverage
        uvm_config_db#(BNN_FCC_Model #(64))::set(this, "*", "bnn_model", model);
        uvm_config_db#(BNN_FCC_Stimulus #(8))::set(this, "*", "bnn_stimulus", stim);
        uvm_config_db#(bnn_expected_queue)::set(this, "*", "bnn_expected_q", expected_q);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env.cfg_agent.configure_transaction_level(1);
        env.in_agent.configure_transaction_level(1);
        env.out_agent.configure_transaction_level(0);

        // Publish coverage handle so sequences can call sample methods
        uvm_config_db#(bnn_fcc_coverage)::set(this, "*", "bnn_coverage", env.coverage);

        // Topology printout
        print();
    endfunction

    virtual task run_phase(uvm_phase phase);
        bnn_cfg_sequence cfg_seq;
        bnn_image_sequence in_seq;
        axi4s_ready_sequence out_seq;

        phase.raise_objection(this);

        `uvm_info("TEST", "Starting sequences", UVM_LOW)

        cfg_seq = bnn_cfg_sequence::type_id::create("cfg_seq");
        in_seq  = bnn_image_sequence::type_id::create("in_seq");
        out_seq = axi4s_ready_sequence::type_id::create("out_seq");

        fork
            out_seq.start(null);
        join_none

        cfg_seq.start(env.cfg_agent.sequencer);
        in_seq.start(env.in_agent.sequencer);

        #50000;

        phase.drop_objection(this);
    endtask

    // =========================================================================
    // Report phase: coverage summary printout
    // Maps to: filter_base_test.svh pattern (report_phase with get_coverage())
    // =========================================================================
    function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        super.report_phase(phase);

        svr = uvm_report_server::get_server();

        // Pass/Fail banner (filter_base_test pattern)
        if (env.scoreboard.match_count == 0) begin
            `uvm_error(get_type_name(), "TEST FAILED (no tests run).")
        end else if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0) begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST FAILED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end else begin
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "---     TEST PASSED     ---", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------", UVM_NONE)
        end

        // Full coverage summary
        $display("\n=== BNN FCC Coverage Summary ===\n");

        $display("CATEGORY 1: AXI4-Stream Protocol Patterns");
        $display("  Config Handshake:      %.2f%%", env.coverage.cg_cfg_handshake.get_coverage());
        $display("  Config Interface:      %.2f%%", env.coverage.cg_cfg_intf.get_coverage());
        $display("  Input Handshake:       %.2f%%", env.coverage.cg_in_handshake.get_coverage());
        $display("  Input Interface:       %.2f%%", env.coverage.cg_in_intf.get_coverage());
        $display("  Output Backpressure:   %.2f%%", env.coverage.cg_out_backpressure.get_coverage());
        $display("  Output Interface:      %.2f%%", env.coverage.cg_out_intf.get_coverage());
        $display("  TKEEP Patterns:        %.2f%%", env.coverage.cg_tkeep.get_coverage());

        $display("\nCATEGORY 2: Configuration Data Diversity");
        $display("  Config Content:        %.2f%%", env.coverage.cg_cfg_content.get_coverage());
        $display("  Weight Density:        %.2f%%", env.coverage.cg_weight_density.get_coverage());
        $display("  Threshold Range:       %.2f%%", env.coverage.cg_thresh.get_coverage());

        $display("\nCATEGORY 3: Computational Stimulus");
        $display("  Output Classes:        %.2f%%", env.coverage.cg_outputs.get_coverage());
        $display("  Output Patterns:       %.2f%%", env.coverage.cg_output_patterns.get_coverage());
        $display("  Workload Diversity:    %.2f%%", env.coverage.cg_workload.get_coverage());

        $display("\nCATEGORY 4: Configuration-Image Sequencing");
        $display("  Reconfig Coverage:     %.2f%%", env.coverage.cg_reconfig.get_coverage());

        $display("\nCATEGORY 5: Reset Scenarios");
        $display("  Reset Coverage:        %.2f%%", env.coverage.cg_reset.get_coverage());
        $display("  Post-Reset Config:     %.2f%%", env.coverage.cg_reset_post.get_coverage());

        $display("\n================================\n");
    endfunction

endclass
`endif
