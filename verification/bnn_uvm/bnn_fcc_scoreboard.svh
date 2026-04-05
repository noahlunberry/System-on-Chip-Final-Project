`ifndef _BNN_FCC_SCOREBOARD_SVH_
`define _BNN_FCC_SCOREBOARD_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;

class bnn_fcc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bnn_fcc_scoreboard)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH ) in_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_axi_item_t;

    // Analysis exports
    uvm_analysis_export #(cfg_axi_item_t) cfg_ae;
    uvm_analysis_export #(in_axi_item_t ) in_ae;
    uvm_analysis_export #(out_axi_item_t) out_ae;

    // FIFOs
    uvm_tlm_analysis_fifo #(cfg_axi_item_t) cfg_fifo;
    uvm_tlm_analysis_fifo #(in_axi_item_t ) in_fifo;
    uvm_tlm_analysis_fifo #(out_axi_item_t) out_fifo;

    // Reference model + stimulus/model config
    BNN_FCC_Model    #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model;

    bit      use_custom_topology;
    int      custom_layers;
    int      custom_topology[];
    string   base_dir;
    bit      verify_model;

    // Status
    bit      cfg_done;
    int      passed;
    int      failed;
    int      image_count;

    // Expected outputs queue
    logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] expected_outputs[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        passed      = 0;
        failed      = 0;
        cfg_done    = 0;
        image_count = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg_ae = new("cfg_ae", this);
        in_ae  = new("in_ae",  this);
        out_ae = new("out_ae", this);

        cfg_fifo = new("cfg_fifo", this);
        in_fifo  = new("in_fifo",  this);
        out_fifo = new("out_fifo", this);

        if (!uvm_config_db#(string)::get(this, "", "base_dir", base_dir))
            `uvm_fatal("NO_BASE_DIR", "base_dir not set")

        if (!uvm_config_db#(bit)::get(this, "", "use_custom_topology", use_custom_topology))
            use_custom_topology = 0;

        if (!uvm_config_db#(bit)::get(this, "", "verify_model", verify_model))
            verify_model = 1;

        // Optional: if you want to pass the actual model handle in through config_db
        if (!uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "model_h", model)) begin
            model = new();
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cfg_ae.connect(cfg_fifo.analysis_export);
        in_ae.connect(in_fifo.analysis_export);
        out_ae.connect(out_fifo.analysis_export);
    endfunction

    // Reconstruct one image vector from an input packet item.
    function automatic void unpack_input_image(
        input  in_axi_item_t pkt,
        output bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] img[]
    );
        int valid_elems = 0;
        int beat_idx, elem_idx;
        int elems_per_beat;
        int bytes_per_elem;

        elems_per_beat = bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH / bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH;
        bytes_per_elem = bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH / 8;

        // Count valid elements using tkeep
        foreach (pkt.tdata[beat_idx]) begin
            for (elem_idx = 0; elem_idx < elems_per_beat; elem_idx++) begin
                if (pkt.tkeep[beat_idx][elem_idx*bytes_per_elem +: bytes_per_elem] == '1)
                    valid_elems++;
            end
        end

        img = new[valid_elems];
        valid_elems = 0;

        foreach (pkt.tdata[beat_idx]) begin
            for (elem_idx = 0; elem_idx < elems_per_beat; elem_idx++) begin
                if (pkt.tkeep[beat_idx][elem_idx*bytes_per_elem +: bytes_per_elem] == '1) begin
                    img[valid_elems] =
                        pkt.tdata[beat_idx][elem_idx*bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH +:
                                           bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH];
                    valid_elems++;
                end
            end
        end
    endfunction

    task process_config();
        cfg_axi_item_t cfg_pkt;
        forever begin
            cfg_fifo.get(cfg_pkt);

            // For now, simply mark cfg_done when the final configuration packet arrives.
            // If you later make reconfiguration tests, this is where epoch tracking belongs.
            if (cfg_pkt.tlast.size() > 0 && cfg_pkt.tlast[cfg_pkt.tlast.size()-1]) begin
                cfg_done = 1'b1;
                `uvm_info("SCOREBOARD", "Configuration stream completed.", UVM_LOW)
            end
        end
    endtask

    task process_inputs();
        in_axi_item_t in_pkt;
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        int expected_pred;

        forever begin
            in_fifo.get(in_pkt);

            if (!cfg_done) begin
                `uvm_warning("SCOREBOARD", "Received input packet before config completed.")
            end

            unpack_input_image(in_pkt, current_img);
            expected_pred = model.compute_reference(current_img);
            expected_outputs.push_back(expected_pred[bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0]);

            `uvm_info("SCOREBOARD",
                      $sformatf("Queued expected output %0d for image %0d.",
                                expected_pred, image_count),
                      UVM_LOW)
            image_count++;
        end
    endtask

    task process_outputs();
        out_axi_item_t out_pkt;
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] actual;
        logic [bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0] expected;

        forever begin
            out_fifo.get(out_pkt);

            if (expected_outputs.size() == 0) begin
                `uvm_error("SCOREBOARD", "Observed DUT output with no queued expected output.")
                failed++;
                continue;
            end

            actual   = out_pkt.tdata[0][bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];
            expected = expected_outputs.pop_front();

            if (actual == expected) begin
                `uvm_info("SCOREBOARD",
                          $sformatf("PASS: actual=%0d expected=%0d", actual, expected),
                          UVM_LOW)
                passed++;
            end
            else begin
                `uvm_error("SCOREBOARD",
                           $sformatf("FAIL: actual=%0d expected=%0d", actual, expected))
                failed++;
            end
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        fork
            process_config();
            process_inputs();
            process_outputs();
        join_none
    endtask

endclass

`endif