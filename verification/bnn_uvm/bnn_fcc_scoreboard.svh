`ifndef _BNN_FCC_SCOREBOARD_SVH_
`define _BNN_FCC_SCOREBOARD_SVH_

`include "uvm_macros.svh"
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

    int passed;
    int failed;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        passed = 0;
        failed = 0;
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

    virtual task run_phase(uvm_phase phase);
        cfg_axi_item_t cfg_pkt;
        in_axi_item_t  in_pkt;
        out_axi_item_t out_pkt;

        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] actual;
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] expected;

        int expected_pred;
        int image_idx;

        image_idx = 0;

        // The config monitor is set to packet level in the env, so a single
        // get() here means the full configuration stream has completed.
        cfg_fifo.get(cfg_pkt);
        `uvm_info("SCOREBOARD", "Configuration stream completed.", UVM_LOW)

        forever begin
            // Read one input packet and one output packet, like the mult example.
            in_fifo.get(in_pkt);
            out_fifo.get(out_pkt);

            unpack_input_image(in_pkt, current_img);
            if (current_img.size() != model.topology[0]) begin
                `uvm_error("SCOREBOARD",
                           $sformatf("Input image %0d had %0d elements, expected %0d.",
                                     image_idx, current_img.size(), model.topology[0]))
                failed++;
                continue;
            end

            expected_pred = model.compute_reference(current_img);
            expected      = expected_pred[bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];

            if (out_pkt.tdata.size() == 0) begin
                `uvm_error("SCOREBOARD", "Observed output packet with no data beats.")
                failed++;
                continue;
            end

            actual = out_pkt.tdata[0][bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];

            if (actual == expected) begin
                `uvm_info("SCOREBOARD",
                          $sformatf("PASS image %0d: actual=%0d expected=%0d",
                                    image_idx, actual, expected),
                          UVM_LOW)
                passed++;
            end
            else begin
                `uvm_error("SCOREBOARD",
                           $sformatf("FAIL image %0d: actual=%0d expected=%0d",
                                     image_idx, actual, expected))
                failed++;
            end

            image_idx++;
        end
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
                  $sformatf("Scoreboard summary: passed=%0d failed=%0d", passed, failed),
                  UVM_NONE)
    endfunction

endclass

`endif
