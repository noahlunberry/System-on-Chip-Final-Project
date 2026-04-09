`ifndef _BNN_FCC_SCOREBOARD_SVH_
`define _BNN_FCC_SCOREBOARD_SVH_

`include "uvm_macros.svh"
`include "bnn_fcc_perf_trackers.svh"
import uvm_pkg::*;
import axi4_stream_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bnn_fcc_scoreboard)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH ) in_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_axi_item_t;

    // Analysis exports (sinks of analysis ports)
    uvm_analysis_export #(cfg_axi_item_t) cfg_ae;
    uvm_analysis_export #(in_axi_item_t ) in_ae;
    uvm_analysis_export #(out_axi_item_t) out_ae;

    // Analysis FIFOs
    uvm_tlm_analysis_fifo #(cfg_axi_item_t) cfg_fifo;
    uvm_tlm_analysis_fifo #(in_axi_item_t ) in_fifo;
    uvm_tlm_analysis_fifo #(out_axi_item_t) out_fifo;

    // Reference model
    BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model;
    BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) active_model;
    bnn_fcc_latency_tracker latency;
    bnn_fcc_throughput_tracker throughput;

    virtual bnn_fcc_ctrl_if ctrl_vif;
    real clock_period_ns;

    // Reset/reconfiguration support is based on queueing expectations at input
    // time instead of assuming a strict "next input immediately matches next
    // output" flow. Each queued entry records the prediction, the logical
    // image index, and the configuration epoch that produced it.
    semaphore state_sem;
    int expected_pred_q[$];
    int expected_image_idx_q[$];
    int expected_epoch_q[$];
    int next_input_idx;
    // config_epoch increments every time a new configuration is committed to
    // the scoreboard. This lets logs show which model snapshot produced each
    // checked output.
    int config_epoch;
    int observed_cfg_packets;
    // configured/drop_outputs_until_configured gate scoreboard checking across
    // reset boundaries. After reset, outputs are ignored until the test tells
    // the scoreboard which model should now be considered active.
    bit configured;
    bit drop_outputs_until_configured;

    int passed;
    int failed;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        passed = 0;
        failed = 0;
        next_input_idx = 0;
        config_epoch = 0;
        observed_cfg_packets = 0;
        configured = 1'b0;
        drop_outputs_until_configured = 1'b1;
        state_sem = new(1);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create the analysis exports.
        cfg_ae = new("cfg_ae", this);
        in_ae  = new("in_ae",  this);
        out_ae = new("out_ae", this);

        // Create the analysis FIFOs.
        cfg_fifo = new("cfg_fifo", this);
        in_fifo  = new("in_fifo",  this);
        out_fifo = new("out_fifo", this);

        if (!uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "model_h", model))
            `uvm_fatal("NO_MODEL", "Scoreboard could not find shared model_h.")

        if (!model.is_loaded)
            `uvm_fatal("MODEL_NOT_LOADED", "Scoreboard received an unloaded model handle.")

        active_model = new();
        if (!uvm_config_db#(real)::get(this, "", "clock_period_ns", clock_period_ns))
            clock_period_ns = 1.0;
        latency = new(clock_period_ns);
        throughput = new(clock_period_ns);

        if (!uvm_config_db#(virtual bnn_fcc_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
            `uvm_warning("NO_CTRL_VIF", "Scoreboard could not find ctrl_vif. Mid-test reset cleanup will be disabled.")
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect the FIFOs to the analysis exports so the scoreboard can
        // read transactions from the FIFOs just like the mult example.
        cfg_ae.connect(cfg_fifo.analysis_export);
        in_ae.connect(in_fifo.analysis_export);
        out_ae.connect(out_fifo.analysis_export);
    endfunction

    // Reconstruct one image vector from a packetized input transaction.
    function automatic void unpack_input_image(
        input  in_axi_item_t pkt,
        output bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] img[]
    );
        int valid_elems;
        int beat_idx, elem_idx;
        int elems_per_beat;

        valid_elems   = 0;
        elems_per_beat = bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH / bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH;

        // Count valid elements using tkeep.
        foreach (pkt.tdata[beat_idx]) begin
            for (elem_idx = 0; elem_idx < elems_per_beat; elem_idx++) begin
                if (pkt.tkeep[beat_idx][elem_idx*(bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH/8) +:
                                        (bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH/8)] == '1)
                    valid_elems++;
            end
        end

        img = new[valid_elems];
        valid_elems = 0;

        // Unpack valid elements.
        foreach (pkt.tdata[beat_idx]) begin
            for (elem_idx = 0; elem_idx < elems_per_beat; elem_idx++) begin
                if (pkt.tkeep[beat_idx][elem_idx*(bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH/8) +:
                                        (bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH/8)] == '1) begin
                    img[valid_elems] =
                        pkt.tdata[beat_idx][elem_idx*bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH +:
                                            bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH];
                    valid_elems++;
                end
            end
        end
    endfunction

    task commit_model(
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model_h,
        string tag = "configuration"
    );
        // Tests call commit_model() after sending configuration traffic. The
        // scoreboard copies the model rather than storing the handle directly
        // so later test-side edits cannot retroactively change expectations.
        if (model_h == null)
            `uvm_fatal("NULL_MODEL", "Scoreboard commit_model() received a null model handle.")

        if (!model_h.is_loaded)
            `uvm_fatal("UNLOADED_MODEL", "Scoreboard commit_model() received an unloaded model.")

        state_sem.get(1);
        active_model.copy_from(model_h);
        config_epoch++;
        configured = 1'b1;
        drop_outputs_until_configured = 1'b0;
        state_sem.put(1);

        `uvm_info("SCOREBOARD",
                  $sformatf("Committed model for %s at config epoch %0d.", tag, config_epoch),
                  UVM_LOW)
    endtask

    task wait_for_idle();
        // Used by tests that need to know when all predictions computed so far
        // have either been matched to outputs or dropped due to reset.
        forever begin
            bit is_idle;

            state_sem.get(1);
            is_idle = (expected_pred_q.size() == 0);
            state_sem.put(1);

            if (is_idle)
                break;

            if (ctrl_vif != null)
                @(posedge ctrl_vif.clk);
            else
                #1ns;
        end
    endtask

    protected task handle_reset_cleanup();
        int dropped_outputs;

        // Any queued expectations were created under the pre-reset model and
        // can no longer be trusted once reset fires, so we throw them away and
        // force the test to commit a fresh post-reset model.
        state_sem.get(1);
        dropped_outputs = expected_pred_q.size();
        foreach (expected_image_idx_q[i])
            latency.clear_event(expected_image_idx_q[i]);
        expected_pred_q.delete();
        expected_image_idx_q.delete();
        expected_epoch_q.delete();
        configured = 1'b0;
        drop_outputs_until_configured = 1'b1;
        state_sem.put(1);

        `uvm_info("SCOREBOARD",
                  $sformatf("Observed reset. Cleared %0d pending expected outputs and marked scoreboard unconfigured.",
                            dropped_outputs),
                  UVM_LOW)
    endtask

    task monitor_config_stream();
        cfg_axi_item_t cfg_pkt;

        // The scoreboard does not decode configuration packets itself. This
        // thread exists mainly for visibility and debugging so we can tell
        // whether configuration traffic was observed when expected.
        forever begin
            cfg_fifo.get(cfg_pkt);
            observed_cfg_packets++;
            `uvm_info("SCOREBOARD",
                      $sformatf("Observed configuration packet %0d with %0d beats.",
                                observed_cfg_packets, cfg_pkt.tdata.size()),
                      UVM_HIGH)
        end
    endtask

    task monitor_resets();
        if (ctrl_vif == null)
            return;

        // Reset observation is separate from input/output processing so the
        // cleanup happens immediately when reset asserts.
        forever begin
            @(posedge ctrl_vif.rst);
            handle_reset_cleanup();
        end
    endtask

    task process_inputs();
        in_axi_item_t in_pkt;
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        int expected_pred;

        // Input packets are converted into queued expectations as soon as they
        // arrive. This decouples prediction generation from when the DUT later
        // emits the classification result.
        forever begin
            int image_idx;

            in_fifo.get(in_pkt);

            if (in_pkt.tdata.size() == 0) begin
                `uvm_warning("SCOREBOARD", "Observed input packet with no data beats.")
                continue;
            end

            unpack_input_image(in_pkt, current_img);

            state_sem.get(1);
            if (!configured) begin
                state_sem.put(1);
                `uvm_error("SCOREBOARD", "Observed input packet before a model was committed to the scoreboard.")
                failed++;
                continue;
            end

            if (current_img.size() != active_model.topology[0]) begin
                state_sem.put(1);
                `uvm_error("SCOREBOARD",
                           $sformatf("Input image %0d had %0d elements, expected %0d.",
                                     next_input_idx, current_img.size(), active_model.topology[0]))
                failed++;
                continue;
            end

            // Snapshot the prediction using the currently committed model and
            // remember which configuration epoch it belongs to.
            expected_pred = active_model.compute_reference(current_img);
            image_idx = next_input_idx;
            next_input_idx++;
            expected_pred_q.push_back(expected_pred);
            expected_image_idx_q.push_back(image_idx);
            expected_epoch_q.push_back(config_epoch);
            if (in_pkt.first_beat_time > 0.0) begin
                if (image_idx == 0)
                    throughput.start_test_at(in_pkt.first_beat_time);
                latency.start_event_at(image_idx, in_pkt.first_beat_time);
            end
            else begin
                if (image_idx == 0)
                    throughput.start_test();
                latency.start_event(image_idx);
            end
            state_sem.put(1);
        end
    endtask

    task process_outputs();
        out_axi_item_t out_pkt;
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] actual;
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] expected;
        int expected_pred;
        int image_idx;
        int expected_cfg_epoch;
        bit ignore_output;

        // Outputs consume the queued expectations in order. If reset happened
        // and no new model has been committed yet, outputs are intentionally
        // ignored rather than compared against stale pre-reset predictions.
        forever begin
            out_fifo.get(out_pkt);

            if (out_pkt.tdata.size() == 0) begin
                `uvm_error("SCOREBOARD", "Observed output packet with no data beats.")
                failed++;
                continue;
            end

            state_sem.get(1);
            ignore_output = drop_outputs_until_configured;

            if (!ignore_output && expected_pred_q.size() != 0) begin
                expected_pred = expected_pred_q.pop_front();
                image_idx = expected_image_idx_q.pop_front();
                expected_cfg_epoch = expected_epoch_q.pop_front();
            end
            else begin
                expected_pred = 0;
                image_idx = -1;
                expected_cfg_epoch = -1;
            end

            state_sem.put(1);

            if (ignore_output) begin
                `uvm_info("SCOREBOARD",
                          "Ignoring output packet while scoreboard is waiting for a committed post-reset configuration.",
                          UVM_HIGH)
                continue;
            end

            if (image_idx < 0) begin
                `uvm_error("SCOREBOARD", "Observed output packet with no matching expected result queued.")
                failed++;
                continue;
            end

            // The DUT only returns the compact classification code, so the
            // full integer prediction from the reference model is truncated to
            // the configured output width before comparison.
            expected = expected_pred[bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];
            actual = out_pkt.tdata[0][bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];

            if (actual == expected) begin
                `uvm_info("SCOREBOARD",
                          $sformatf("PASS image %0d (epoch %0d): actual=%0d expected=%0d",
                                    image_idx, expected_cfg_epoch, actual, expected),
                          UVM_LOW)
                passed++;
            end
            else begin
                `uvm_error("SCOREBOARD",
                           $sformatf("FAIL image %0d (epoch %0d): actual=%0d expected=%0d",
                                     image_idx, expected_cfg_epoch, actual, expected))
                failed++;
            end

            if (out_pkt.last_beat_time > 0.0) begin
                latency.end_event_at(image_idx, out_pkt.last_beat_time);
                throughput.sample_end_at(out_pkt.last_beat_time);
            end
            else begin
                latency.end_event(image_idx);
                throughput.sample_end();
            end
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        // Keep configuration observation, reset tracking, expectation creation,
        // and output comparison in independent threads so they can react to
        // traffic concurrently.
        fork
            monitor_config_stream();
            monitor_resets();
            process_inputs();
            process_outputs();
        join
    endtask

    function void report_phase(uvm_phase phase);
        int total_checked;

        super.report_phase(phase);
        total_checked = passed + failed;
        `uvm_info("SCOREBOARD",
                  $sformatf("Scoreboard summary: passed=%0d failed=%0d", passed, failed),
                  UVM_NONE)
        `uvm_info("SCOREBOARD",
                  $sformatf("Avg latency (cycles) per image: %0.1f cycles", latency.get_avg_cycles()),
                  UVM_NONE)
        `uvm_info("SCOREBOARD",
                  $sformatf("Avg latency (time) per image: %0.1f ns", latency.get_avg_time()),
                  UVM_NONE)
        `uvm_info("SCOREBOARD",
                  $sformatf("Avg throughput (outputs/sec): %0.1f", throughput.get_outputs_per_sec(total_checked)),
                  UVM_NONE)
        `uvm_info("SCOREBOARD",
                  $sformatf("Avg throughput (cycles/output): %0.1f", throughput.get_avg_cycles_per_output(total_checked)),
                  UVM_NONE)
    endfunction

endclass

`endif
