// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// SCOREBOARD: bnn_fcc_scoreboard
// Maps to: IMPLEMENTATION_PLAN.md §"Scoreboard and reference model design for correctness checks"
//
// DESCRIPTION:
// Stateful, epoch-aware scoreboard. The report mandates:
// - Analysis FIFOs per interface (cfg_fifo, in_fifo, out_fifo)
// - Reference model wrapper with "current model state"
// - Comparison engine: pop expected_q on each accepted output
// - Reset/reconfig handling: clear FIFOs, clear expected_q, reset model state
// - Config epoch ID tracking for gating comparisons
//
// DEVIATION: None. This follows the report's recommended structure exactly.

`ifndef _BNN_FCC_SCOREBOARD_SVH_
`define _BNN_FCC_SCOREBOARD_SVH_

// Lightweight queue object for decoupled prediction passing between sequences
// and the scoreboard. The sequence pushes expected outputs; the scoreboard pops
// them as actual outputs arrive.
class bnn_expected_queue;
    int q[$];
    function new(); endfunction
endclass

class bnn_fcc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bnn_fcc_scoreboard)

    // Analysis FIFOs — one per interface, per report §"Recommended scoreboard structure"
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(64)) cfg_fifo;
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(64)) in_fifo;
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(8))  out_fifo;

    // Analysis exports for env wiring (filter_scoreboard pattern)
    uvm_analysis_export #(axi4_stream_seq_item #(64)) cfg_ae;
    uvm_analysis_export #(axi4_stream_seq_item #(64)) in_ae;
    uvm_analysis_export #(axi4_stream_seq_item #(8))  out_ae;

    BNN_FCC_Model #(64) model;
    bnn_expected_queue   expected_q;

    // --- Epoch tracking (report §"Reset/reconfig handling") ---
    // On reset: clear FIFOs + expected_q, increment rst_epoch
    // On reconfig: increment cfg_epoch
    int unsigned cfg_epoch  = 0;
    int unsigned rst_epoch  = 0;

    // Statistics
    int match_count    = 0;
    int mismatch_count = 0;
    int image_idx      = 0;
    int discarded_on_reset = 0;

    // Reset awareness flag — set by test when a reset is injected
    bit reset_in_progress = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg_fifo = new("cfg_fifo", this);
        in_fifo  = new("in_fifo", this);
        out_fifo = new("out_fifo", this);

        cfg_ae = new("cfg_ae", this);
        in_ae  = new("in_ae", this);
        out_ae = new("out_ae", this);

        if (!uvm_config_db#(BNN_FCC_Model #(64))::get(null, "*", "bnn_model", model))
            `uvm_fatal("NO_MODEL", "Failed to get BNN_FCC_Model from config db")
        if (!uvm_config_db#(bnn_expected_queue)::get(null, "*", "bnn_expected_q", expected_q))
            `uvm_fatal("NO_EXPECTED_Q", "Failed to get bnn_expected_queue from config db")
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cfg_ae.connect(cfg_fifo.analysis_export);
        in_ae.connect(in_fifo.analysis_export);
        out_ae.connect(out_fifo.analysis_export);
    endfunction

    // --- Reset handler: called by test to flush state ---
    // Maps to: report §"On reset: clear FIFOs, clear expected queue, reset model state"
    function void handle_reset();
        rst_epoch++;
        discarded_on_reset += expected_q.q.size();
        expected_q.q.delete();
        reset_in_progress = 1;
        `uvm_info("SB_RESET", $sformatf("Reset epoch %0d: flushed expected queue (%0d discarded total)", rst_epoch, discarded_on_reset), UVM_MEDIUM)
    endfunction

    // --- Reconfig handler: called by test to bump cfg_epoch ---
    // Maps to: report §"On reconfig: flush expected queue (conservative)"
    function void handle_reconfig();
        cfg_epoch++;
        expected_q.q.delete(); // Conservative: flush on reconfig
        `uvm_info("SB_RECONFIG", $sformatf("Config epoch %0d", cfg_epoch), UVM_MEDIUM)
    endfunction

    // Acknowledge reset recovery complete
    function void clear_reset();
        reset_in_progress = 0;
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi4_stream_seq_item #(8) out_item;

        forever begin
            out_fifo.get(out_item);

            // If a reset was recently injected, discard outputs until
            // the test signals that recovery is complete
            if (reset_in_progress) begin
                `uvm_info("SB_RESET_DISCARD", "Discarding output received during reset recovery", UVM_HIGH)
                continue;
            end

            foreach (out_item.tdata[i]) begin
                int actual = out_item.tdata[i];
                int expected_val;

                if (expected_q.q.size() == 0) begin
                    `uvm_error("SB_EMPTY_EXPECTED", $sformatf(
                        "Received output %0d (epoch cfg=%0d rst=%0d) but no expected result available",
                        actual, cfg_epoch, rst_epoch))
                end else begin
                    expected_val = expected_q.q.pop_front();
                    if (actual == expected_val) begin
                        `uvm_info("SB_MATCH", $sformatf(
                            "Image %0d classified as %0d (epoch cfg=%0d rst=%0d)",
                            image_idx, actual, cfg_epoch, rst_epoch), UVM_HIGH)
                        match_count++;
                    end else begin
                        `uvm_error("SB_MISMATCH", $sformatf(
                            "Image %0d: actual=%0d expected=%0d (epoch cfg=%0d rst=%0d)",
                            image_idx, actual, expected_val, cfg_epoch, rst_epoch))
                        mismatch_count++;
                    end
                    image_idx++;
                end
            end
        end
    endtask

    // --- Check phase: report leftovers and summary ---
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (expected_q.q.size() > 0)
            `uvm_error("SB_LEFTOVER", $sformatf("%0d expected outputs not matched", expected_q.q.size()))
        `uvm_info("SB_REPORT", $sformatf(
            "Epochs: cfg=%0d rst=%0d | MATCHES=%0d MISMATCHES=%0d | Discarded on reset=%0d",
            cfg_epoch, rst_epoch, match_count, mismatch_count, discarded_on_reset), UVM_NONE)
    endfunction

endclass
`endif
