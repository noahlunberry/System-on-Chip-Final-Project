// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// SEQUENCE: bnn_cfg_sequence
// Maps to: IMPLEMENTATION_PLAN.md §"Configuration sequence with ordering + tvalid pattern shaping"
//
// DESCRIPTION:
// Configuration sequence with per-layer-message granularity. Each (layer, msg_type) pair
// is a separate message that can be reordered. Supports:
//   - reorder_msgs:           shuffle all messages randomly
//   - thresh_before_weights:  send all thresholds before weights
//   - reverse_layer_order:    configure layers in reverse order
//
// Each message is sent as an individual AXI packet (is_packet_level=1).
// After each message send, we sample cg_cfg_content + cg_weight_density + cg_thresh
// via the coverage component.
//
// DEVIATION from prior code: Was monolithic single-packet. Now per-message, matching
// the report's sequence pseudocode exactly.

`ifndef _BNN_CFG_SEQUENCE_SVH_
`define _BNN_CFG_SEQUENCE_SVH_

// Lightweight struct for a single config message (layer + type)
class bnn_cfg_msg;
    int  layer_id;
    bit  is_threshold;
    bit [63:0] data_stream[];
    bit [7:0]  keep_stream[];
    function new(int lid, bit is_t);
        layer_id = lid;
        is_threshold = is_t;
    endfunction
endclass

class bnn_cfg_sequence extends uvm_sequence #(axi4_stream_seq_item #(64));
    `uvm_object_utils(bnn_cfg_sequence)

    BNN_FCC_Model #(64) model;

    // Ordering knobs (coverage_plan.txt Cat 1: "Vary ordering of weight/threshold messages")
    rand bit reorder_msgs;
    rand bit thresh_before_weights;
    rand bit reverse_layer_order;

    // Default: standard order
    constraint c_order_default {
        soft reorder_msgs == 0;
        soft thresh_before_weights == 0;
        soft reverse_layer_order == 0;
    }

    function new(string name="bnn_cfg_sequence");
        super.new(name);
    endfunction

    virtual task body();
        bnn_cfg_msg msgs[$];
        bnn_fcc_coverage cov;
        bit [63:0] layer_data[];
        bit [7:0]  layer_keep[];

        if (!uvm_config_db#(BNN_FCC_Model #(64))::get(null, "*", "bnn_model", model))
            `uvm_fatal("NO_MODEL", "Failed to get BNN_FCC_Model from config db")

        // 1) Build per-message list: one msg per (layer, weight/threshold)
        //    Matches report: "Build msgs[]: one per (layer, msg_type)"
        for (int l = 0; l < model.num_layers; l++) begin
            bnn_cfg_msg w_msg, t_msg;
            // Weights message
            w_msg = new(l, 0);
            model.get_layer_config(l, 0, layer_data, layer_keep);
            w_msg.data_stream = layer_data;
            w_msg.keep_stream = layer_keep;
            msgs.push_back(w_msg);

            // Thresholds message (skip output layer per model convention)
            if (l < model.num_layers - 1) begin
                t_msg = new(l, 1);
                model.get_layer_config(l, 1, layer_data, layer_keep);
                t_msg.data_stream = layer_data;
                t_msg.keep_stream = layer_keep;
                msgs.push_back(t_msg);
            end
        end

        // 2) Apply ordering policies (coverage_plan.txt Cat 1 + 4)
        if (reorder_msgs) begin
            msgs.shuffle();
            `uvm_info("CFG_SEQ", "Messages shuffled randomly", UVM_MEDIUM)
        end else if (thresh_before_weights) begin
            // Sort: thresholds first, then weights
            begin
                bnn_cfg_msg sorted[$];
                foreach (msgs[i]) if (msgs[i].is_threshold) sorted.push_back(msgs[i]);
                foreach (msgs[i]) if (!msgs[i].is_threshold) sorted.push_back(msgs[i]);
                msgs = sorted;
            end
            `uvm_info("CFG_SEQ", "Thresholds before weights ordering", UVM_MEDIUM)
        end else if (reverse_layer_order) begin
            begin
                bnn_cfg_msg reversed[$];
                for (int i = msgs.size()-1; i >= 0; i--) reversed.push_back(msgs[i]);
                msgs = reversed;
            end
            `uvm_info("CFG_SEQ", "Reverse layer order", UVM_MEDIUM)
        end

        // Try to get coverage handle for sampling
        void'(uvm_config_db#(bnn_fcc_coverage)::get(null, "*", "bnn_coverage", cov));

        // 3) Send each message as a separate AXI packet
        foreach (msgs[i]) begin
            axi4_stream_seq_item#(64) req = axi4_stream_seq_item#(64)::type_id::create($sformatf("cfg_msg_%0d", i));

            start_item(req);
            req.is_packet_level = 1;
            req.tdata = new[msgs[i].data_stream.size()];
            req.tkeep = new[msgs[i].keep_stream.size()];
            req.tstrb = new[msgs[i].keep_stream.size()];

            foreach (msgs[i].data_stream[j]) begin
                req.tdata[j] = msgs[i].data_stream[j];
                req.tkeep[j] = msgs[i].keep_stream[j];
                req.tstrb[j] = msgs[i].keep_stream[j];
            end
            finish_item(req);

            // Sample coverage: msg_type × layer_id × order
            if (cov != null) begin
                cov.sample_cfg_msg(msgs[i].is_threshold, msgs[i].layer_id, i);

                // Sample weight density for this layer
                if (!msgs[i].is_threshold) begin
                    int ones = 0;
                    int total = 0;
                    for (int n = 0; n < model.weight[msgs[i].layer_id].size(); n++) begin
                        for (int b = 0; b < model.weight[msgs[i].layer_id][n].size(); b++) begin
                            if (model.weight[msgs[i].layer_id][n][b]) ones++;
                            total++;
                        end
                    end
                    if (total > 0)
                        cov.sample_weight_density((ones * 100) / total, msgs[i].layer_id);
                end

                // Sample threshold magnitude for this layer
                if (msgs[i].is_threshold) begin
                    for (int n = 0; n < model.threshold[msgs[i].layer_id].size(); n++) begin
                        cov.sample_thresh(model.threshold[msgs[i].layer_id][n], msgs[i].layer_id);
                    end
                end
            end
        end
    endtask
endclass
`endif
