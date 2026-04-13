// Pawin Ruangkanit
// University of Florida
//
// This file implements transaction-level coverage for the BNN FCC UVM
// environment. The overall structure closely follows the mult_coverage
// example: each stream has a dedicated coverage component with an analysis
// export, FIFO, and local covergroups.

`ifndef _BNN_FCC_COVERAGE_SVH_
`define _BNN_FCC_COVERAGE_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi4_stream_pkg::*;
import bnn_fcc_tb_pkg::*;


// Toggle coverage for the configuration stream. As in the mult_coverage
// example, this is sampled manually for each observed bit position.
covergroup cfg_toggle_coverage with function sample(input int index, input bit value);
    index_cp: coverpoint index {
        bins indexes[] = {[0 : bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH - 1]};
        option.weight = 0;
    }

    value_cp: coverpoint value {
        bins set = {1};
        bins cleared = {0};
        option.weight = 0;
    }

    toggle_cp: cross index_cp, value_cp;
endgroup


// Toggle coverage for individual input pixels after reconstructing them from
// the packet-level AXI transactions.
covergroup input_toggle_coverage with function sample(input int index, input bit value);
    index_cp: coverpoint index {
        bins indexes[] = {[0 : bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH - 1]};
        option.weight = 0;
    }

    value_cp: coverpoint value {
        bins set = {1};
        bins cleared = {0};
        option.weight = 0;
    }

    toggle_cp: cross index_cp, value_cp;
endgroup


// Toggle coverage for the classification output bits.
covergroup output_toggle_coverage with function sample(input int index, input bit value);
    index_cp: coverpoint index {
        bins indexes[] = {[0 : bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH - 1]};
        option.weight = 0;
    }

    value_cp: coverpoint value {
        bins set = {1};
        bins cleared = {0};
        option.weight = 0;
    }

    toggle_cp: cross index_cp, value_cp;
endgroup


class bnn_cfg_coverage extends uvm_component;
    `uvm_component_utils(bnn_cfg_coverage)

    // Reuse the fully parameterized AXI item type for the config stream.
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) axi_item_t;

    localparam int CONFIG_BYTES_PER_BEAT = bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH / 8;

    // Analysis export/FIFO pair so this component can receive transactions
    // directly from the packet-level config monitor.
    uvm_analysis_export #(axi_item_t) cfg_ae;
    uvm_tlm_analysis_fifo #(axi_item_t) cfg_fifo;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_vif;

    // State used by the covergroups below.
    int packet_num_beats;
    int packet_last_valid_bytes;
    int sideband_tid;
    int sideband_tdest;
    int sideband_tuser;

    int msg_type;
    int layer_id;
    int bytes_per_neuron;
    int total_payload_bytes;
    int weight_density_pct;
    int threshold_value;
    int threshold_ratio_pct;
    int msg_transition_kind;
    int layer_transition_kind;
    int cfg_gap_len;
    int cfg_burst_len;
    int max_cfg_layer_id;
    int max_threshold_layer_id;
    int max_design_threshold_value;
    int threshold_small_limit;
    int threshold_medium_limit;

    // Covers coarse packet-level protocol properties such as full vs. partial
    // final beats.
    covergroup packet_coverage;
        num_beats_cp: coverpoint packet_num_beats {
            bins single = {1};
            bins short_pkt = {[2:16]};
            bins medium_pkt = {[17:64]};
            bins long_pkt = {[65:4096]};
        }

        last_valid_bytes_cp: coverpoint packet_last_valid_bytes {
            bins partial = {[1:CONFIG_BYTES_PER_BEAT-1]};
            bins full = {CONFIG_BYTES_PER_BEAT};
        }
    endgroup

    // Covers the AXI sideband fields even though the current tests mostly
    // drive them to zero.
    covergroup sideband_coverage;
        tid_cp: coverpoint sideband_tid {
            bins zero = {0};
            bins nonzero = default;
        }

        tdest_cp: coverpoint sideband_tdest {
            bins zero = {0};
            bins nonzero = default;
        }

        tuser_cp: coverpoint sideband_tuser {
            bins zero = {0};
            bins nonzero = default;
        }
    endgroup

    // Covers the decoded configuration header fields from each message.
    covergroup header_coverage;
        msg_type_cp: coverpoint msg_type {
            bins weights = {0};
            bins thresholds = {1};
            illegal_bins invalid = default;
        }

        layer_id_cp: coverpoint layer_id {
            bins legal_layers[] = {[0:max_cfg_layer_id]};
            illegal_bins invalid = default;
        }

        bytes_per_neuron_cp: coverpoint bytes_per_neuron {
            bins one = {1};
            bins small_bin = {[2:4]};
            bins medium_bin = {[5:16]};
            bins large_bin = {[17:4096]};
        }

        payload_bytes_cp: coverpoint total_payload_bytes {
            bins tiny = {[1:64]};
            bins small_bin = {[65:256]};
            bins medium_bin = {[257:1024]};
            bins large_bin = {[1025:1048576]};
        }

        msg_layer_cross: cross msg_type_cp, layer_id_cp {
            // The DUT only accepts threshold messages for hidden layers.
            ignore_bins threshold_on_output =
                binsof(msg_type_cp) intersect {1} &&
                binsof(layer_id_cp) intersect {max_cfg_layer_id};
        }
    endgroup

    // Covers ordering of configuration traffic across message types and layers.
    covergroup order_coverage;
        msg_transition_cp: coverpoint msg_transition_kind {
            bins first = {0};
            bins same_type = {1};
            bins weights_to_thresholds = {2};
            bins thresholds_to_weights = {3};
        }

        layer_transition_cp: coverpoint layer_transition_kind {
            bins first = {0};
            bins same_layer = {1};
            bins next_layer = {2};
            bins backwards = {3};
            bins jump = {4};
        }

        order_cross: cross msg_transition_cp, layer_transition_cp;
    endgroup

    // Covers the density of 1s in each neuron's weight pattern.
    covergroup weight_density_coverage;
        layer_id_cp: coverpoint layer_id {
            bins legal_layers[] = {[0:max_cfg_layer_id]};
            illegal_bins invalid = default;
            option.weight = 0;
        }

        density_cp: coverpoint weight_density_pct {
            bins zero = {0};
            bins sparse = {[1:25]};
            bins medium_bin = {[26:75]};
            bins dense = {[76:99]};
            bins full = {100};
        }

        density_cross: cross layer_id_cp, density_cp;
    endgroup

    // Covers threshold magnitudes and their size relative to the layer fan-in.
    covergroup threshold_coverage;
        layer_id_cp: coverpoint layer_id {
            bins hidden_layers[] = {[0:max_threshold_layer_id]};
            illegal_bins invalid = default;
            option.weight = 0;
        }

        threshold_abs_cp: coverpoint threshold_value {
            bins negative = {[$:-1]};
            bins zero = {0};
            bins low = {[1:threshold_small_limit]};
            bins medium_bin = {[threshold_small_limit + 1:threshold_medium_limit]};
            bins high = {[threshold_medium_limit + 1:max_design_threshold_value]};
            bins above_design = {[max_design_threshold_value + 1:$]};
        }

        threshold_ratio_cp: coverpoint threshold_ratio_pct {
            bins unknown = {-1};
            bins zero = {0};
            bins low = {[1:33]};
            bins medium_bin = {[34:66]};
            bins high = {[67:4096]};
        }

        threshold_cross: cross layer_id_cp, threshold_ratio_cp;
    endgroup

    // Covers cycle-level TVALID gap/burst behavior on the config interface.
    // This complements the packet-level header/content coverage above; it is
    // specifically aimed at the coverage-plan items about handshake timing and
    // intermittent versus bursty TVALID patterns.
    covergroup cfg_handshake_coverage;
        gap_len_cp: coverpoint cfg_gap_len {
            bins zero = {0};
            bins short_gap = {[1:3]};
            bins medium_gap = {[4:15]};
            bins long_gap = {[16:$]};
        }

        burst_len_cp: coverpoint cfg_burst_len {
            bins one = {1};
            bins short_burst = {[2:4]};
            bins long_burst = {[5:32]};
            bins huge_burst = {[33:$]};
        }
    endgroup

    // Covers live valid/ready/backpressure observations.
    covergroup cfg_interface_coverage;
        valid_cp: coverpoint cfg_vif.tvalid { bins hi = {1}; bins lo = {0}; }
        ready_cp: coverpoint cfg_vif.tready { bins hi = {1}; bins lo = {0}; }
        backpressure_cp: coverpoint (!cfg_vif.tready && cfg_vif.tvalid) { bins seen = {1}; }
    endgroup

    // As in the mult example, this extra covergroup is instantiated explicitly
    // because it is sampled manually rather than through a class property name.
    cfg_toggle_coverage config_toggle_cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        max_cfg_layer_id = bnn_fcc_uvm_pkg::TRAINED_LAYERS - 2;
        max_threshold_layer_id = (max_cfg_layer_id > 0) ? (max_cfg_layer_id - 1) : 0;
        max_design_threshold_value = 0;

        for (int i = 0; i < bnn_fcc_uvm_pkg::TRAINED_LAYERS - 1; i++) begin
            if (bnn_fcc_uvm_pkg::TRAINED_TOPOLOGY[i] > max_design_threshold_value)
                max_design_threshold_value = bnn_fcc_uvm_pkg::TRAINED_TOPOLOGY[i];
        end

        if (max_design_threshold_value < 3)
            max_design_threshold_value = 3;

        threshold_small_limit = max_design_threshold_value / 3;
        if (threshold_small_limit < 1)
            threshold_small_limit = 1;

        threshold_medium_limit = (2 * max_design_threshold_value) / 3;
        if (threshold_medium_limit < threshold_small_limit)
            threshold_medium_limit = threshold_small_limit;

        packet_coverage = new();
        sideband_coverage = new();
        header_coverage = new();
        order_coverage = new();
        weight_density_coverage = new();
        threshold_coverage = new();
        cfg_handshake_coverage = new();
        cfg_interface_coverage = new();
        config_toggle_cov = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create the analysis export and FIFO.
        cfg_ae = new("cfg_ae", this);
        cfg_fifo = new("cfg_fifo", this);

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "cfg_vif", cfg_vif))
            `uvm_warning("CFG_COV_NO_VIF", "Could not get cfg_vif for config interface coverage.")
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect the export to the FIFO so run_phase() can pull complete
        // packet-level transactions just like in the mult coverage example.
        cfg_ae.connect(cfg_fifo.analysis_export);
    endfunction

    // Counts the number of valid bytes in the final beat using TKEEP.
    function automatic int count_valid_bytes(input logic [CONFIG_BYTES_PER_BEAT-1:0] keep_word);
        int count;

        count = 0;
        for (int i = 0; i < CONFIG_BYTES_PER_BEAT; i++) begin
            if (keep_word[i])
                count++;
        end

        return count;
    endfunction

    // Converts a packetized AXI config transaction into a byte queue so the
    // header/payload fields can be decoded more easily.
    function automatic void unpack_cfg_bytes(input axi_item_t pkt, output bit [7:0] byte_q[$]);
        byte_q.delete();

        foreach (pkt.tdata[beat_idx]) begin
            for (int byte_idx = 0; byte_idx < CONFIG_BYTES_PER_BEAT; byte_idx++) begin
                if (pkt.tkeep[beat_idx][byte_idx])
                    byte_q.push_back(pkt.tdata[beat_idx][byte_idx*8 +: 8]);
            end
        end
    endfunction

    // Counts the number of 1 bits in a packed weight row while ignoring any
    // byte-padding bits added during configuration encoding.
    function automatic int count_weight_ones(
        input bit [7:0] byte_q[$],
        input int start_idx,
        input int bytes_per_row,
        input int valid_bits
    );
        int ones;
        int bit_count;

        ones = 0;
        bit_count = 0;

        for (int byte_idx = 0; byte_idx < bytes_per_row; byte_idx++) begin
            bit [7:0] curr_byte;

            curr_byte = byte_q[start_idx + byte_idx];

            for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                if (bit_count >= valid_bits)
                    return ones;

                if (curr_byte[bit_idx])
                    ones++;

                bit_count++;
            end
        end

        return ones;
    endfunction

    // Thresholds are encoded as 32-bit little-endian integers.
    function automatic int unpack_threshold(input bit [7:0] byte_q[$], input int start_idx);
        bit [31:0] raw_value;

        raw_value = {byte_q[start_idx + 3], byte_q[start_idx + 2],
                     byte_q[start_idx + 1], byte_q[start_idx + 0]};

        return $signed(raw_value);
    endfunction

    // Classifies the transition between adjacent config message types.
    function automatic int classify_msg_transition(
        input bit prev_valid,
        input int prev_msg_type,
        input int curr_msg_type
    );
        if (!prev_valid)
            return 0;
        if (prev_msg_type == curr_msg_type)
            return 1;
        if (prev_msg_type == 0 && curr_msg_type == 1)
            return 2;
        return 3;
    endfunction

    // Classifies the transition between adjacent layer IDs.
    function automatic int classify_layer_transition(
        input bit prev_valid,
        input int prev_layer_id,
        input int curr_layer_id
    );
        if (!prev_valid)
            return 0;
        if (curr_layer_id == prev_layer_id)
            return 1;
        if (curr_layer_id == prev_layer_id + 1)
            return 2;
        if (curr_layer_id < prev_layer_id)
            return 3;
        return 4;
    endfunction

    task sample_cfg_interface();
        int gap_cnt;
        int burst_cnt;

        if (cfg_vif == null)
            return;

        gap_cnt = 0;
        burst_cnt = 0;

        forever begin
            @(posedge cfg_vif.aclk);

            if (!cfg_vif.aresetn) begin
                gap_cnt = 0;
                burst_cnt = 0;
                continue;
            end

            cfg_interface_coverage.sample();

            if (cfg_vif.tvalid && cfg_vif.tready) begin
                cfg_gap_len = gap_cnt;
                cfg_burst_len = burst_cnt + 1;
                cfg_handshake_coverage.sample();
                burst_cnt++;
                gap_cnt = 0;
            end
            else if (cfg_vif.tvalid && !cfg_vif.tready) begin
                // Hold the current burst open until the transfer completes.
            end
            else begin
                if (burst_cnt > 0)
                    burst_cnt = 0;
                gap_cnt++;
            end
        end
    endtask

    task sample_cfg_transactions();
        axi_item_t cfg_pkt;
        bit [7:0] cfg_bytes[$];
        int layer_inputs_by_layer[int];
        bit prev_msg_valid;
        int prev_msg_type;
        int prev_layer_id;

        cfg_pkt = new();
        prev_msg_valid = 1'b0;
        prev_msg_type = 0;
        prev_layer_id = 0;

        forever begin
            int cursor;

            // Read one complete configuration packet from the monitor.
            cfg_fifo.get(cfg_pkt);

            if (cfg_pkt.tdata.size() == 0) begin
                `uvm_warning("CFG_COV", "Observed empty configuration packet.")
                continue;
            end

            packet_num_beats = cfg_pkt.tdata.size();
            packet_last_valid_bytes = count_valid_bytes(cfg_pkt.tkeep[cfg_pkt.tkeep.size() - 1]);
            sideband_tid = cfg_pkt.tid;
            sideband_tdest = cfg_pkt.tdest;
            sideband_tuser = cfg_pkt.tuser;

            packet_coverage.sample();
            sideband_coverage.sample();

            // Manually sample every observed configuration bit for toggle
            // coverage.
            foreach (cfg_pkt.tdata[beat_idx]) begin
                for (int bit_idx = 0; bit_idx < bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH; bit_idx++)
                    config_toggle_cov.sample(bit_idx, cfg_pkt.tdata[beat_idx][bit_idx]);
            end

            unpack_cfg_bytes(cfg_pkt, cfg_bytes);
            cursor = 0;

            // A single AXI packet can contain multiple config messages, so walk
            // through the byte stream one decoded header at a time.
            while ((cursor + 16) <= cfg_bytes.size()) begin
                int layer_inputs;
                int n_neurons;
                int payload_start;
                int payload_end;

                msg_type = cfg_bytes[cursor + 0];
                layer_id = cfg_bytes[cursor + 1];
                layer_inputs = {cfg_bytes[cursor + 3], cfg_bytes[cursor + 2]};
                n_neurons = {cfg_bytes[cursor + 5], cfg_bytes[cursor + 4]};
                bytes_per_neuron = {cfg_bytes[cursor + 7], cfg_bytes[cursor + 6]};
                total_payload_bytes = {cfg_bytes[cursor + 11], cfg_bytes[cursor + 10],
                                       cfg_bytes[cursor + 9], cfg_bytes[cursor + 8]};

                msg_transition_kind = classify_msg_transition(prev_msg_valid, prev_msg_type, msg_type);
                layer_transition_kind = classify_layer_transition(prev_msg_valid, prev_layer_id, layer_id);

                header_coverage.sample();
                order_coverage.sample();

                payload_start = cursor + 16;
                payload_end = payload_start + total_payload_bytes;

                if (payload_end > cfg_bytes.size()) begin
                    `uvm_warning("CFG_COV",
                                 $sformatf("Malformed config packet: payload end %0d exceeds packet byte count %0d.",
                                           payload_end, cfg_bytes.size()))
                    break;
                end

                if (msg_type == 0) begin
                    // Weight message: cache the layer fan-in and sample the
                    // density of 1s for each neuron row.
                    layer_inputs_by_layer[layer_id] = layer_inputs;

                    for (int neuron_idx = 0; neuron_idx < n_neurons; neuron_idx++) begin
                        int ones;

                        ones = count_weight_ones(cfg_bytes,
                                                 payload_start + neuron_idx * bytes_per_neuron,
                                                 bytes_per_neuron,
                                                 layer_inputs);

                        weight_density_pct = (layer_inputs > 0) ? ((ones * 100) / layer_inputs) : 0;
                        weight_density_coverage.sample();
                    end
                end
                else if (msg_type == 1) begin
                    int actual_layer_inputs;

                    // Threshold message: use the most recent fan-in for the
                    // same layer to normalize threshold coverage.
                    if (layer_inputs_by_layer.exists(layer_id))
                        actual_layer_inputs = layer_inputs_by_layer[layer_id];
                    else
                        actual_layer_inputs = 0;

                    for (int neuron_idx = 0; neuron_idx < n_neurons; neuron_idx++) begin
                        threshold_value = unpack_threshold(cfg_bytes, payload_start + neuron_idx * 4);
                        threshold_ratio_pct = (actual_layer_inputs > 0) ?
                                              ((threshold_value * 100) / actual_layer_inputs) : -1;
                        threshold_coverage.sample();
                    end
                end
                else begin
                    `uvm_warning("CFG_COV",
                                 $sformatf("Observed unsupported config msg_type=%0d for layer %0d.",
                                           msg_type, layer_id))
                end

                prev_msg_valid = 1'b1;
                prev_msg_type = msg_type;
                prev_layer_id = layer_id;
                cursor = payload_end;
            end

            if (cursor != cfg_bytes.size()) begin
                `uvm_warning("CFG_COV",
                             $sformatf("Configuration packet ended with %0d unparsed bytes.",
                                       cfg_bytes.size() - cursor))
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            sample_cfg_interface();
            sample_cfg_transactions();
        join
    endtask
endclass


class bnn_input_coverage extends uvm_component;
    `uvm_component_utils(bnn_input_coverage)

    // AXI item type for the image-input stream.
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) axi_item_t;

    localparam int INPUTS_PER_BEAT = bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH / bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH;
    localparam int BYTES_PER_INPUT = bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH / 8;
    localparam int INPUT_BINARIZATION_THRESHOLD = 1 << (bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH - 1);
    localparam int PIXEL_MAX_VALUE = (1 << bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH) - 1;
    localparam int PIXEL_LOWER_SPLIT = INPUT_BINARIZATION_THRESHOLD / 2;
    localparam int PIXEL_UPPER_SPLIT =
        INPUT_BINARIZATION_THRESHOLD + ((PIXEL_MAX_VALUE - INPUT_BINARIZATION_THRESHOLD) / 2);

    // Analysis export/FIFO pair for packet-level image transactions.
    uvm_analysis_export #(axi_item_t) in_ae;
    uvm_tlm_analysis_fifo #(axi_item_t) in_fifo;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) in_vif;

    // State sampled by the covergroups below.
    int image_num_beats;
    int image_num_pixels;
    int last_beat_valid_inputs;
    int pixel_value;
    int sideband_tid;
    int sideband_tdest;
    int sideband_tuser;
    int in_gap_len;
    int in_burst_len;
    int inter_image_gap;
    int num_images_seen;
    int expected_image_num_pixels;

    // Covers packet shapes for streamed images, including partial final beats.
    covergroup image_coverage;
        num_beats_cp: coverpoint image_num_beats {
            bins single = {1};
            bins short_pkt = {[2:4]};
            bins medium_pkt = {[5:8]};
            bins long_pkt = {[9:256]};
        }

        num_pixels_cp: coverpoint image_num_pixels {
            bins expected = {expected_image_num_pixels};
            illegal_bins unexpected = default;
        }

        last_beat_valid_inputs_cp: coverpoint last_beat_valid_inputs {
            bins partial = {[1:INPUTS_PER_BEAT-1]};
            bins full = {INPUTS_PER_BEAT};
        }

        image_shape_cross: cross num_beats_cp, last_beat_valid_inputs_cp;
    endgroup

    // Covers image pixel values after reconstructing the original stimulus
    // vector from TDATA/TKEEP.
    covergroup pixel_coverage;
        pixel_cp: coverpoint pixel_value {
            bins zero = {0};
            bins low_far = {[1:PIXEL_LOWER_SPLIT-1]};
            bins low_near = {[PIXEL_LOWER_SPLIT:INPUT_BINARIZATION_THRESHOLD-1]};
            bins at_threshold = {INPUT_BINARIZATION_THRESHOLD};
            bins high_near = {[INPUT_BINARIZATION_THRESHOLD+1:PIXEL_UPPER_SPLIT]};
            bins high_far = {[PIXEL_UPPER_SPLIT+1:PIXEL_MAX_VALUE-1]};
            bins max_ = {PIXEL_MAX_VALUE};
            illegal_bins invalid = default;
        }

        pixel_extremes_cp: coverpoint pixel_value {
            bins zero = {0};
            bins low = {[1:63]};
            bins mid = {[64:191]};
            bins high = {[192:254]};
            bins max_ = {255};
        }
    endgroup

    // Covers the AXI sideband fields on the input stream.
    covergroup sideband_coverage;
        tid_cp: coverpoint sideband_tid {
            bins zero = {0};
            bins nonzero = default;
        }

        tdest_cp: coverpoint sideband_tdest {
            bins zero = {0};
            bins nonzero = default;
        }

        tuser_cp: coverpoint sideband_tuser {
            bins zero = {0};
            bins nonzero = default;
        }
    endgroup

    // Covers cycle-level TVALID gaps/bursts during image transfers.
    covergroup input_handshake_coverage;
        gap_len_cp: coverpoint in_gap_len {
            bins zero = {0};
            bins short_gap = {[1:3]};
            bins medium_gap = {[4:15]};
            bins long_gap = {[16:$]};
        }

        burst_len_cp: coverpoint in_burst_len {
            bins one = {1};
            bins short_burst = {[2:4]};
            bins long_burst = {[5:32]};
            bins huge_burst = {[33:$]};
        }
    endgroup

    // Covers spacing between completed images.
    covergroup input_image_spacing_coverage;
        inter_image_gap_cp: coverpoint inter_image_gap {
            bins zero = {0};
            bins short_gap = {[1:5]};
            bins medium_gap = {[6:20]};
            bins long_gap = {[21:$]};
        }
    endgroup

    // Covers live valid/ready/backpressure observations on the input stream.
    covergroup input_interface_coverage;
        valid_cp: coverpoint in_vif.tvalid { bins hi = {1}; bins lo = {0}; }
        ready_cp: coverpoint in_vif.tready { bins hi = {1}; bins lo = {0}; }
        backpressure_cp: coverpoint (!in_vif.tready && in_vif.tvalid) { bins seen = {1}; }
    endgroup

    // Covers the running workload size across a test.
    covergroup workload_coverage;
        num_images_cp: coverpoint num_images_seen {
            bins few = {[1:5]};
            bins some = {[6:20]};
            bins many = {[21:100]};
            bins stress = {[101:$]};
        }
    endgroup

    // Manual toggle coverage for the bits of each input pixel.
    input_toggle_coverage pixel_toggle_cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        expected_image_num_pixels = bnn_fcc_uvm_pkg::TRAINED_TOPOLOGY[0];
        image_coverage = new();
        pixel_coverage = new();
        sideband_coverage = new();
        input_handshake_coverage = new();
        input_image_spacing_coverage = new();
        input_interface_coverage = new();
        workload_coverage = new();
        pixel_toggle_cov = new();
        num_images_seen = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create the export and FIFO.
        in_ae = new("in_ae", this);
        in_fifo = new("in_fifo", this);

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH))::get(this, "", "in_vif", in_vif))
            `uvm_warning("INPUT_COV_NO_VIF", "Could not get in_vif for input interface coverage.")
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect the export to the FIFO.
        in_ae.connect(in_fifo.analysis_export);
    endfunction

    // Count how many individual inputs are valid in one beat by inspecting
    // TKEEP a pixel at a time.
    function automatic int count_valid_inputs(input logic [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH/8-1:0] keep_word);
        int count;

        count = 0;

        for (int elem_idx = 0; elem_idx < INPUTS_PER_BEAT; elem_idx++) begin
            if (keep_word[elem_idx*BYTES_PER_INPUT +: BYTES_PER_INPUT] == '1)
                count++;
        end

        return count;
    endfunction

    // Rebuild the original image vector from the packetized AXI input item.
    function automatic void unpack_input_image(
        input axi_item_t pkt,
        output bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] img[]
    );
        int valid_elems;

        valid_elems = 0;
        foreach (pkt.tdata[beat_idx]) begin
            valid_elems += count_valid_inputs(pkt.tkeep[beat_idx]);
        end

        img = new[valid_elems];
        valid_elems = 0;

        foreach (pkt.tdata[beat_idx]) begin
            for (int elem_idx = 0; elem_idx < INPUTS_PER_BEAT; elem_idx++) begin
                if (pkt.tkeep[beat_idx][elem_idx*BYTES_PER_INPUT +: BYTES_PER_INPUT] == '1) begin
                    img[valid_elems] = pkt.tdata[beat_idx][elem_idx*bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH +:
                                                           bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH];
                    valid_elems++;
                end
            end
        end
    endfunction

    task sample_input_interface();
        int gap_cnt;
        int burst_cnt;
        int image_gap_cnt;
        bit waiting_for_image_start;

        if (in_vif == null)
            return;

        gap_cnt = 0;
        burst_cnt = 0;
        image_gap_cnt = 0;
        waiting_for_image_start = 0;

        forever begin
            @(posedge in_vif.aclk);

            if (!in_vif.aresetn) begin
                gap_cnt = 0;
                burst_cnt = 0;
                image_gap_cnt = 0;
                waiting_for_image_start = 0;
                continue;
            end

            input_interface_coverage.sample();

            if (in_vif.tvalid && in_vif.tready) begin
                in_gap_len = gap_cnt;
                in_burst_len = burst_cnt + 1;
                input_handshake_coverage.sample();

                if (waiting_for_image_start) begin
                    inter_image_gap = image_gap_cnt;
                    input_image_spacing_coverage.sample();
                    image_gap_cnt = 0;
                    waiting_for_image_start = 0;
                end

                burst_cnt++;
                gap_cnt = 0;

                if (in_vif.tlast) begin
                    waiting_for_image_start = 1;
                    image_gap_cnt = 0;
                end
            end
            else if (in_vif.tvalid && !in_vif.tready) begin
                // Keep the current burst active until the beat transfers.
            end
            else begin
                if (burst_cnt > 0)
                    burst_cnt = 0;
                gap_cnt++;

                if (waiting_for_image_start)
                    image_gap_cnt++;
            end
        end
    endtask

    task sample_input_transactions();
        axi_item_t in_pkt;
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];

        in_pkt = new();

        forever begin
            // Read one full image packet from the monitor.
            in_fifo.get(in_pkt);

            if (in_pkt.tdata.size() == 0) begin
                `uvm_warning("INPUT_COV", "Observed empty input packet.")
                continue;
            end

            unpack_input_image(in_pkt, current_img);

            image_num_beats = in_pkt.tdata.size();
            image_num_pixels = current_img.size();
            last_beat_valid_inputs = count_valid_inputs(in_pkt.tkeep[in_pkt.tkeep.size() - 1]);
            sideband_tid = in_pkt.tid;
            sideband_tdest = in_pkt.tdest;
            sideband_tuser = in_pkt.tuser;
            num_images_seen++;

            image_coverage.sample();
            sideband_coverage.sample();
            workload_coverage.sample();

            // Sample both value coverage and per-bit toggle coverage for every
            // reconstructed pixel.
            foreach (current_img[i]) begin
                pixel_value = current_img[i];
                pixel_coverage.sample();

                for (int bit_idx = 0; bit_idx < bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH; bit_idx++)
                    pixel_toggle_cov.sample(bit_idx, current_img[i][bit_idx]);
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            sample_input_interface();
            sample_input_transactions();
        join
    endtask
endclass


class bnn_output_coverage extends uvm_component;
    `uvm_component_utils(bnn_output_coverage)

    // AXI item type for the classification-output stream.
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) axi_item_t;

    localparam int OUTPUT_BYTES_PER_BEAT = bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH / 8;
    localparam int MAX_OUTPUT_CLASS = (9);

    // Analysis export/FIFO pair for observed outputs.
    uvm_analysis_export #(axi_item_t) out_ae;
    uvm_tlm_analysis_fifo #(axi_item_t) out_fifo;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_vif;

    // State sampled by the covergroups.
    int output_class;
    int output_valid_bytes;
    int output_transition_kind;
    int sideband_tid;
    int sideband_tdest;
    int sideband_tuser;
    int out_stall_len;
    int out_ready_burst_len;
    int output_backpressure_bin;
    int repeat_run_len;

    bit prev_output_valid;
    int prev_output_class;

    // Covers observed output classes and whether successive outputs repeat or
    // change.
    covergroup output_coverage;
        class_cp: coverpoint output_class {
            bins classes[] = {[0:MAX_OUTPUT_CLASS]};
        }

        transition_cp: coverpoint output_transition_kind {
            bins first = {0};
            bins repeated = {1};
            bins changed = {2};
        }

        valid_bytes_cp: coverpoint output_valid_bytes {
            bins full = {OUTPUT_BYTES_PER_BEAT};
            illegal_bins empty = {0};
        }

        backpressure_cp: coverpoint output_backpressure_bin {
            bins none = {0};
            bins light = {1};
            bins heavy = {2};
        }

        class_transition_cross: cross class_cp, transition_cp;
        class_backpressure_cross: cross class_cp, backpressure_cp;
    endgroup

    // Covers the AXI sideband fields on the output stream.
    covergroup sideband_coverage;
        tid_cp: coverpoint sideband_tid {
            bins zero = {0};
            bins nonzero = default;
        }

        tdest_cp: coverpoint sideband_tdest {
            bins zero = {0};
            bins nonzero = default;
        }

        tuser_cp: coverpoint sideband_tuser {
            bins zero = {0};
            bins nonzero = default;
        }
    endgroup

    // Covers observed TREADY stall and burst patterns on the output stream.
    covergroup output_backpressure_coverage;
        stall_len_cp: coverpoint out_stall_len {
            bins zero = {0};
            bins short_stall = {[1:3]};
            bins medium_stall = {[4:15]};
            bins long_stall = {[16:$]};
        }

        ready_burst_cp: coverpoint out_ready_burst_len {
            bins one = {1};
            bins short_burst = {[2:5]};
            bins long_burst = {[6:$]};
        }
    endgroup

    // Covers live valid/ready/backpressure observations on the output stream.
    covergroup output_interface_coverage;
        valid_cp: coverpoint out_vif.tvalid { bins hi = {1}; bins lo = {0}; }
        ready_cp: coverpoint out_vif.tready { bins hi = {1}; bins lo = {0}; }
        backpressure_cp: coverpoint (!out_vif.tready && out_vif.tvalid) { bins seen = {1}; }
    endgroup

    // Covers repeated output-class run lengths.
    covergroup output_pattern_coverage;
        repeat_len_cp: coverpoint repeat_run_len {
            bins single = {1};
            bins short_run = {[2:3]};
            bins medium_run = {[4:10]};
            bins long_run = {[11:$]};
        }
    endgroup

    // Manual toggle coverage for the output classification bits.
    output_toggle_coverage output_toggle_cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);

        output_coverage = new();
        sideband_coverage = new();
        output_backpressure_coverage = new();
        output_interface_coverage = new();
        output_pattern_coverage = new();
        output_toggle_cov = new();
        prev_output_valid = 1'b0;
        prev_output_class = 0;
        repeat_run_len = 0;
        output_backpressure_bin = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create the export and FIFO.
        out_ae = new("out_ae", this);
        out_fifo = new("out_fifo", this);

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH))::get(this, "", "out_vif", out_vif))
            `uvm_warning("OUTPUT_COV_NO_VIF", "Could not get out_vif for output interface coverage.")
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect the export to the FIFO.
        out_ae.connect(out_fifo.analysis_export);
    endfunction

    // Counts the number of valid bytes in the observed output beat.
    function automatic int count_valid_bytes(input logic [OUTPUT_BYTES_PER_BEAT-1:0] keep_word);
        int count;

        count = 0;
        for (int i = 0; i < OUTPUT_BYTES_PER_BEAT; i++) begin
            if (keep_word[i])
                count++;
        end

        return count;
    endfunction

    task sample_output_interface();
        int stall_cnt;
        int ready_cnt;

        if (out_vif == null)
            return;

        stall_cnt = 0;
        ready_cnt = 0;

        forever begin
            @(posedge out_vif.aclk);

            if (!out_vif.aresetn) begin
                stall_cnt = 0;
                ready_cnt = 0;
                output_backpressure_bin = 0;
                continue;
            end

            output_interface_coverage.sample();

            if (out_vif.tready) begin
                ready_cnt++;

                if (stall_cnt > 0) begin
                    out_stall_len = stall_cnt;
                    output_backpressure_coverage.sample();
                    output_backpressure_bin = (stall_cnt < 5) ? 1 : 2;
                    stall_cnt = 0;
                end
                else begin
                    output_backpressure_bin = 0;
                end
            end
            else begin
                stall_cnt++;

                if (ready_cnt > 0) begin
                    out_ready_burst_len = ready_cnt;
                    output_backpressure_coverage.sample();
                    ready_cnt = 0;
                end
            end
        end
    endtask

    task sample_output_transactions();
        axi_item_t out_pkt;

        out_pkt = new();

        forever begin
            // Read one output packet from the monitor.
            out_fifo.get(out_pkt);

            if (out_pkt.tdata.size() == 0) begin
                `uvm_warning("OUTPUT_COV", "Observed empty output packet.")
                continue;
            end

            output_class = out_pkt.tdata[0][bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH-1:0];
            output_valid_bytes = count_valid_bytes(out_pkt.tkeep[0]);
            output_transition_kind = !prev_output_valid ? 0 :
                                     ((output_class == prev_output_class) ? 1 : 2);
            sideband_tid = out_pkt.tid;
            sideband_tdest = out_pkt.tdest;
            sideband_tuser = out_pkt.tuser;

            output_coverage.sample();
            sideband_coverage.sample();

            if (!prev_output_valid || output_class != prev_output_class) begin
                if (prev_output_valid && repeat_run_len > 0)
                    output_pattern_coverage.sample();
                repeat_run_len = 1;
            end
            else begin
                repeat_run_len++;
            end

            // Manually sample bit-toggle coverage for the classification code.
            for (int bit_idx = 0; bit_idx < bnn_fcc_uvm_pkg::OUTPUT_DATA_WIDTH; bit_idx++)
                output_toggle_cov.sample(bit_idx, output_class[bit_idx]);

            prev_output_valid = 1'b1;
            prev_output_class = output_class;
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            sample_output_interface();
            sample_output_transactions();
        join
    endtask
endclass


class bnn_system_coverage extends uvm_component;
    `uvm_component_utils(bnn_system_coverage)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) in_axi_item_t;

    uvm_analysis_export #(in_axi_item_t) in_ae;
    uvm_tlm_analysis_fifo #(in_axi_item_t) in_fifo;

    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_vif;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) in_vif;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_vif;
    virtual bnn_fcc_ctrl_if ctrl_vif;

    // This component gathers cross-stream events that are awkward to infer
    // from a single monitor alone: what kind of reconfiguration was intended,
    // when reset occurred relative to live traffic, and how much work had been
    // issued before the reset happened.
    int reconfig_type;
    int layers_touched;
    int reset_phase;
    int reset_count;
    int workload_before_reset;
    bit post_reset_same_cfg;
    int images_since_reset;

    covergroup reconfig_coverage;
        type_cp: coverpoint reconfig_type {
            bins full = {bnn_fcc_uvm_pkg::BNN_RECONFIG_FULL};
            bins weights_only = {bnn_fcc_uvm_pkg::BNN_RECONFIG_WEIGHTS_ONLY};
            bins thresh_only = {bnn_fcc_uvm_pkg::BNN_RECONFIG_THRESH_ONLY};
            bins partial = {bnn_fcc_uvm_pkg::BNN_RECONFIG_PARTIAL};
        }

        layers_cp: coverpoint layers_touched {
            bins one = {1};
            bins some = {[2:3]};
            bins all = {[4:$]};
        }
    endgroup

    covergroup reset_coverage;
        phase_cp: coverpoint reset_phase {
            bins idle = {bnn_fcc_uvm_pkg::BNN_RESET_IDLE};
            bins during_config = {bnn_fcc_uvm_pkg::BNN_RESET_DURING_CONFIG};
            bins during_image = {bnn_fcc_uvm_pkg::BNN_RESET_DURING_IMAGE};
            bins during_output = {bnn_fcc_uvm_pkg::BNN_RESET_DURING_OUTPUT};
            bins at_tlast = {bnn_fcc_uvm_pkg::BNN_RESET_AT_TLAST};
        }

        count_cp: coverpoint reset_count {
            bins one = {1};
            bins few = {[2:3]};
            bins many = {[4:$]};
        }

        workload_cp: coverpoint workload_before_reset {
            bins zero = {0};
            bins few = {[1:5]};
            bins some = {[6:20]};
            bins many = {[21:$]};
        }

        phase_count_cross: cross phase_cp, count_cp;
    endgroup

    covergroup reset_post_coverage;
        same_cfg_cp: coverpoint post_reset_same_cfg {
            bins different = {0};
            bins same = {1};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        reconfig_coverage = new();
        reset_coverage = new();
        reset_post_coverage = new();
        images_since_reset = 0;
        reset_count = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        in_ae = new("in_ae", this);
        in_fifo = new("in_fifo", this);

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "cfg_vif", cfg_vif))
            `uvm_warning("SYS_COV_NO_CFG_VIF", "Could not get cfg_vif for system coverage.")

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH))::get(this, "", "in_vif", in_vif))
            `uvm_warning("SYS_COV_NO_IN_VIF", "Could not get in_vif for system coverage.")

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH))::get(this, "", "out_vif", out_vif))
            `uvm_warning("SYS_COV_NO_OUT_VIF", "Could not get out_vif for system coverage.")

        if (!uvm_config_db#(virtual bnn_fcc_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
            `uvm_warning("SYS_COV_NO_CTRL_VIF", "Could not get ctrl_vif for system coverage.")
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        in_ae.connect(in_fifo.analysis_export);
    endfunction

    function automatic int classify_reset_phase();
        // Infer the most useful reset bucket from the live interface state at
        // the instant reset asserts. "AT_TLAST" takes priority because it is a
        // more specific and more interesting case than generic config/image/output.
        if (((cfg_vif != null) && cfg_vif.tvalid && cfg_vif.tready && cfg_vif.tlast) ||
            ((in_vif != null) && in_vif.tvalid && in_vif.tready && in_vif.tlast) ||
            ((out_vif != null) && out_vif.tvalid && out_vif.tready && out_vif.tlast))
            return bnn_fcc_uvm_pkg::BNN_RESET_AT_TLAST;

        if ((cfg_vif != null) && (cfg_vif.tvalid || cfg_vif.tready))
            return bnn_fcc_uvm_pkg::BNN_RESET_DURING_CONFIG;

        if ((in_vif != null) && (in_vif.tvalid || in_vif.tready))
            return bnn_fcc_uvm_pkg::BNN_RESET_DURING_IMAGE;

        if ((out_vif != null) && (out_vif.tvalid || out_vif.tready))
            return bnn_fcc_uvm_pkg::BNN_RESET_DURING_OUTPUT;

        return bnn_fcc_uvm_pkg::BNN_RESET_IDLE;
    endfunction

    function void sample_reconfig(
        bnn_fcc_uvm_pkg::bnn_reconfig_kind_e kind,
        int num_layers
    );
        // Tests call this directly after issuing a configuration phase. That
        // avoids having the coverage component reverse-engineer intent from the
        // packet stream when the test already knows the scenario.
        reconfig_type = kind;
        layers_touched = num_layers;
        reconfig_coverage.sample();
    endfunction

    function void sample_post_reset(bit same_cfg);
        // Sample whether the post-reset configuration intentionally reused the
        // previous model or switched to a different one.
        post_reset_same_cfg = same_cfg;
        reset_post_coverage.sample();
    endfunction

    task count_input_images();
        in_axi_item_t in_pkt;

        // Keep a running count of images launched since the last reset so the
        // reset covergroup can bucket resets by workload already in flight.
        forever begin
            in_fifo.get(in_pkt);
            if (in_pkt.tdata.size() != 0)
                images_since_reset++;
        end
    endtask

    task monitor_resets();
        if (ctrl_vif == null)
            return;

        // Reset sampling runs independently so the phase/workload snapshot is
        // taken immediately on reset assertion.
        forever begin
            @(posedge ctrl_vif.rst);
            reset_count++;
            reset_phase = classify_reset_phase();
            workload_before_reset = images_since_reset;
            reset_coverage.sample();
            images_since_reset = 0;
        end
    endtask

    task run_phase(uvm_phase phase);
        fork
            count_input_images();
            monitor_resets();
        join
    endtask
endclass

`endif
