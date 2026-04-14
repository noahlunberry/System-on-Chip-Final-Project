// Pawin Ruangkanit
// University of Florida
//
// Directed UVM test that deterministically exercises back-to-back, short,
// medium, and long idle windows on configuration traffic, inter-image spacing
// / data_in_valid, and output data_out_ready backpressure.

`ifndef _BNN_FCC_DELAY_GAP_PROFILE_TEST_SVH_
`define _BNN_FCC_DELAY_GAP_PROFILE_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_config_gap_beat_sequence extends bnn_fcc_config_beat_sequence;
    `uvm_object_utils(bnn_fcc_config_gap_beat_sequence)

    int gap_cycles[$];

    function new(string name = "bnn_fcc_config_gap_beat_sequence");
        super.new(name);
    endfunction

    function void set_gap_cycles(input int gaps[$]);
        gap_cycles.delete();
        foreach (gaps[i])
            gap_cycles.push_back(gaps[i]);
    endfunction

    virtual task body();
        int count;

        load_sequence_config();
        count = 0;

        if (gap_cycles.size() == 0)
            gap_cycles.push_back(0);

        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            if (i > 0)
                repeat (gap_cycles[(i - 1) % gap_cycles.size()]) @(posedge cfg_vif.aclk);

            req = cfg_axi_item_t::type_id::create($sformatf("cfg_gap_req%0d", count++));
            wait_for_grant();

            req.tdata = new[1];
            req.tstrb = new[1];
            req.tkeep = new[1];

            req.tdata[0] = config_bus_data_stream[i];
            req.tstrb[0] = config_bus_keep_stream[i];
            req.tkeep[0] = config_bus_keep_stream[i];
            req.tlast = (i == config_bus_data_stream.size() - 1);
            req.tid = '0;
            req.tdest = '0;
            req.tuser = '0;
            req.is_packet_level = 1'b0;

            wait_for_valid_slot();
            send_request(req);
            wait_for_item_done();
        end
    endtask
endclass


class bnn_fcc_image_gap_packet_sequence extends bnn_fcc_image_scripted_packet_sequence;
    `uvm_object_utils(bnn_fcc_image_gap_packet_sequence)

    int inter_image_gaps[$];

    function new(string name = "bnn_fcc_image_gap_packet_sequence");
        super.new(name);
    endfunction

    function void set_inter_image_gaps(input int gaps[$]);
        inter_image_gaps.delete();
        foreach (gaps[i])
            inter_image_gaps.push_back(gaps[i]);
    endfunction

    virtual task body();
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH-1:0] packed_data[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH/8-1:0] packed_keep[];

        load_sequence_config();

        if (image_indices.size() == 0)
            `uvm_fatal("NO_SCRIPTED_IMAGES",
                       "Gap-profile image sequence was started without any image indices.")

        if (inter_image_gaps.size() == 0)
            inter_image_gaps.push_back(0);

        foreach (image_indices[list_idx]) begin
            int image_idx;

            if (list_idx > 0)
                repeat (inter_image_gaps[(list_idx - 1) % inter_image_gaps.size()]) @(posedge in_vif.aclk);

            image_idx = image_indices[list_idx];

            if (image_idx < 0 || image_idx >= stim.get_num_vectors())
                `uvm_fatal("BAD_IMAGE_INDEX",
                           $sformatf("Requested scripted image index %0d, but only %0d vectors are loaded.",
                                     image_idx, stim.get_num_vectors()))

            stim.get_vector(image_idx, current_img);
            pack_image(current_img, packed_data, packed_keep);

            req = in_axi_item_t::type_id::create($sformatf("img_gap_req%0d", list_idx));
            wait_for_grant();

            req.tdata = new[packed_data.size()];
            req.tstrb = new[packed_keep.size()];
            req.tkeep = new[packed_keep.size()];

            foreach (packed_data[beat_idx]) begin
                req.tdata[beat_idx] = packed_data[beat_idx];
                req.tstrb[beat_idx] = packed_keep[beat_idx];
                req.tkeep[beat_idx] = packed_keep[beat_idx];
            end

            req.tlast = 1'bX;
            req.tid = '0;
            req.tdest = '0;
            req.tuser = '0;
            req.is_packet_level = 1'b1;

            send_request(req);
            wait_for_item_done();
        end
    endtask
endclass


class bnn_fcc_delay_gap_profile_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_delay_gap_profile_test)

    localparam int SHORT_GAP_CYCLES = 5;
    localparam int MEDIUM_GAP_CYCLES = 20;
    localparam int LONG_GAP_CYCLES = 60;

    function new(string name = "bnn_fcc_delay_gap_profile_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Keep the profile deterministic: the explicit waits in this test own
        // the gap shape, so the baseline driver/probability knobs are pinned.
        uvm_config_db#(int)::set(uvm_root::get(), "*", "cfg_min_driver_delay", 1);
        uvm_config_db#(int)::set(uvm_root::get(), "*", "cfg_max_driver_delay", 1);
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_min_driver_delay", 1);
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_max_driver_delay", 1);
        uvm_config_db#(real)::set(uvm_root::get(), "*", "config_valid_probability", 1.0);
        uvm_config_db#(real)::set(uvm_root::get(), "*", "data_in_valid_probability", 1.0);
        super.build_phase(phase);
    endfunction

    protected task wait_for_output_handshake();
        @(posedge env.out_vif.aclk iff (env.out_vif.tvalid && env.out_vif.tready));
    endtask

    protected task drive_output_ready_gap_profile(input int gap_cycles[$]);
        if (gap_cycles.size() == 0)
            `uvm_fatal("EMPTY_OUTPUT_GAPS", "Output ready gap profile requires at least one gap.")

        ctrl_vif.force_output_ready(1'b1);

        foreach (gap_cycles[i]) begin
            if (gap_cycles[i] > 0) begin
                @(posedge env.out_vif.tvalid);
                ctrl_vif.force_output_ready(1'b0);
                repeat (gap_cycles[i]) @(posedge env.out_vif.aclk);
                ctrl_vif.force_output_ready(1'b1);
            end
            else begin
                ctrl_vif.force_output_ready(1'b1);
            end

            wait_for_output_handshake();
            @(posedge env.out_vif.aclk);
        end

        ctrl_vif.release_output_ready();
    endtask

    task run_phase(uvm_phase phase);
        bnn_fcc_config_gap_beat_sequence cfg_seq;
        bnn_fcc_image_gap_packet_sequence img_seq;
        int config_gaps[$];
        int image_gaps[$];
        int output_ready_gaps[$];
        int image_indices[$];
        int expected_total;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting directed gap-profile test for config_valid, data_in_valid, inter-image spacing, and data_out_ready.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        config_gaps = '{0, SHORT_GAP_CYCLES, MEDIUM_GAP_CYCLES, LONG_GAP_CYCLES};
        image_gaps = '{0, SHORT_GAP_CYCLES, MEDIUM_GAP_CYCLES, LONG_GAP_CYCLES};
        output_ready_gaps = '{0, SHORT_GAP_CYCLES, MEDIUM_GAP_CYCLES, LONG_GAP_CYCLES, 0};
        image_indices = '{0, 1, 2, 3, 4};

        cfg_seq = bnn_fcc_config_gap_beat_sequence::type_id::create("cfg_seq");
        cfg_seq.set_gap_cycles(config_gaps);
        run_config_sequence(cfg_seq, model, "gap-profile full configuration");

        set_runtime_num_images(image_indices.size());
        expected_total = env.scoreboard.passed + env.scoreboard.failed + image_indices.size();

        img_seq = bnn_fcc_image_gap_packet_sequence::type_id::create("img_seq");
        img_seq.set_indices(image_indices);
        img_seq.set_inter_image_gaps(image_gaps);

        fork
            begin
                drive_output_ready_gap_profile(output_ready_gaps);
            end
            begin
                img_seq.start(env.in_agent.sequencer);
            end
        join

        wait_for_scoreboard_total(expected_total);
        set_runtime_num_images(num_test_images);
        ctrl_vif.release_output_ready();

        phase.drop_objection(this);
    endtask
endclass

`endif
