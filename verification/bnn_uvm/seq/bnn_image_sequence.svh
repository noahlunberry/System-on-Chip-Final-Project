// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// SEQUENCE: bnn_image_sequence
// Maps to: IMPLEMENTATION_PLAN.md §"Image/activation sequence with partial last-beat TKEEP"
//
// DESCRIPTION:
// Translates offline image matrices into AXI4 beats. Computes reference model
// predictions and pushes expected results to the shared scoreboard queue.
//
// Coverage plan items addressed:
//   Cat 1: "Vary TVALID patterns during image transfers" — via driver delay knobs
//   Cat 1: "Vary timing between consecutive images" — via inter_image_gap
//   Cat 1: "Use diverse pixel values" — pixel class sampling
//   Cat 1: "Consider partial bus transfers (TKEEP)" — natural from packing

`ifndef _BNN_IMAGE_SEQUENCE_SVH_
`define _BNN_IMAGE_SEQUENCE_SVH_

class bnn_image_sequence extends uvm_sequence #(axi4_stream_seq_item #(64));
    `uvm_object_utils(bnn_image_sequence)

    BNN_FCC_Stimulus #(8) stim;
    BNN_FCC_Model #(64) model;
    bnn_expected_queue expected_q;
    int num_images = 10;

    function new(string name="bnn_image_sequence");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] current_img[];
        int inputs_per_cycle = 64/8;
        bnn_fcc_coverage cov;

        if (!uvm_config_db#(BNN_FCC_Stimulus #(8))::get(null, "*", "bnn_stimulus", stim))
            `uvm_fatal("NO_STIMULUS", "Failed to get BNN_FCC_Stimulus from config db")
        if (!uvm_config_db#(BNN_FCC_Model #(64))::get(null, "*", "bnn_model", model))
            `uvm_fatal("NO_MODEL", "Failed to get BNN_FCC_Model from config db")
        if (!uvm_config_db#(bnn_expected_queue)::get(null, "*", "bnn_expected_q", expected_q))
            `uvm_fatal("NO_EXPECTED_Q", "Failed to get bnn_expected_queue from config db")
        if (!uvm_config_db#(int)::get(null, "*", "num_test_images", num_images))
            `uvm_warning("NO_NUM_TEST", "Could not get num_test_images from DB, using default");

        void'(uvm_config_db#(bnn_fcc_coverage)::get(null, "*", "bnn_coverage", cov));

        for (int i = 0; i < num_images; i++) begin
            axi4_stream_seq_item#(64) req = axi4_stream_seq_item#(64)::type_id::create($sformatf("img_%0d", i));
            int beats;
            int expected_pred;

            stim.get_vector(i, current_img);

            // Register model expectation
            expected_pred = model.compute_reference(current_img);
            expected_q.q.push_back(expected_pred);

            // --- Pixel diversity sampling (coverage_plan Cat 1: "diverse pixel values") ---
            if (cov != null) begin
                bit all_zero = 1;
                bit all_ff = 1;
                foreach (current_img[p]) begin
                    if (current_img[p] != 0) all_zero = 0;
                    if (current_img[p] != 8'hFF) all_ff = 0;
                end
                if (all_zero) cov.sample_pixel(0);
                else if (all_ff) cov.sample_pixel(1);
                else cov.sample_pixel(2);
            end

            beats = (current_img.size() + inputs_per_cycle - 1) / inputs_per_cycle;

            start_item(req);
            req.is_packet_level = 1;
            req.tdata = new[beats];
            req.tkeep = new[beats];
            req.tstrb = new[beats];

            for (int j = 0; j < beats; j++) begin
                bit [63:0] tdata = 0;
                bit [7:0]  tkeep = 0;
                for (int k = 0; k < inputs_per_cycle; k++) begin
                    int idx = j * inputs_per_cycle + k;
                    if (idx < current_img.size()) begin
                        tdata[k*8 +: 8] = current_img[idx];
                        tkeep[k] = 1'b1;
                    end
                end
                req.tdata[j] = tdata;
                req.tkeep[j] = tkeep;
                req.tstrb[j] = tkeep;
            end
            finish_item(req);
        end
    endtask
endclass
`endif
