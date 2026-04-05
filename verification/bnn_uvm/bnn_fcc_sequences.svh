// Greg Stitt
// University of Florida
//
// This file defines both single-beat and packet-level sequences for the
// bnn_fcc design. The overall structure is intentionally very close to the
// accum example: each stream has a base sequence plus beat-level and
// packet-level derived sequences.

`ifndef _BNN_FCC_SEQUENCES_SVH_
`define _BNN_FCC_SEQUENCES_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi4_stream_pkg::*;
import bnn_fcc_tb_pkg::*;


// -----------------------------------------------------------------------------
// Base Configuration Sequence
// -----------------------------------------------------------------------------
// Consumes the shared reference model, then converts that model into the same
// AXI config stream used by the original non-UVM testbench.
virtual class bnn_fcc_config_base_sequence extends
    uvm_sequence #(axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH));
    `uvm_object_utils(bnn_fcc_config_base_sequence)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_axi_item_t;

    bit    is_packet_level;
    real   valid_probability;

    BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_vif;

    bit [bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH-1:0] config_bus_data_stream[];
    bit [bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH/8-1:0] config_bus_keep_stream[];

    function new(string name = "bnn_fcc_config_base_sequence");
        super.new(name);
    endfunction

    // Returns 1 with probability p, mirroring the helper in bnn_fcc_tb.
    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0)
            `uvm_fatal("BAD_VALID_PROB",
                       $sformatf("Configuration valid probability must be in [0.0, 1.0], got %0f.", p))

        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    // Pull the shared model handle from config_db and build the config stream.
    function void load_sequence_config();
        if (!uvm_config_db#(real)::get(null, "", "config_valid_probability", valid_probability))
            valid_probability = 1.0;

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(
                null, "", "cfg_vif", cfg_vif
            ))
            `uvm_fatal("NO_CFG_VIF", "Configuration sequence could not find cfg_vif.")

        if (!uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(null, "", "model_h", model))
            `uvm_fatal("NO_MODEL", "Configuration sequence could not find shared model_h.")

        if (!model.is_loaded)
            `uvm_fatal("MODEL_NOT_LOADED", "Configuration sequence received an unloaded model handle.")

        model.encode_configuration(config_bus_data_stream, config_bus_keep_stream);

        if (config_bus_data_stream.size() == 0)
            `uvm_fatal("EMPTY_CONFIG", "Configuration sequence created an empty config stream.")
    endfunction

    // Wait for a cycle where the producer is allowed to assert TVALID.
    task automatic wait_for_valid_slot();
        while (!chance(valid_probability))
            @(posedge cfg_vif.aclk iff cfg_vif.tready);
    endtask
endclass


// -----------------------------------------------------------------------------
// Beat-Level Configuration Sequence
// -----------------------------------------------------------------------------
// Sends the full model configuration as individual AXI beats. The driver uses
// req.tlast directly in this mode.
class bnn_fcc_config_beat_sequence extends bnn_fcc_config_base_sequence;
    `uvm_object_utils(bnn_fcc_config_beat_sequence)

    function new(string name = "bnn_fcc_config_beat_sequence");
        super.new(name);
        is_packet_level = 1'b0;
    endfunction

    virtual task body();
        int count;

        load_sequence_config();
        count = 0;

        for (int i = 0; i < config_bus_data_stream.size(); i++) begin
            req = cfg_axi_item_t::type_id::create($sformatf("cfg_req%0d", count++));
            wait_for_grant();

            req.tdata = new[1];
            req.tstrb = new[1];
            req.tkeep = new[1];

            req.tdata[0]         = config_bus_data_stream[i];
            req.tstrb[0]         = config_bus_keep_stream[i];
            req.tkeep[0]         = config_bus_keep_stream[i];
            req.tlast            = (i == config_bus_data_stream.size() - 1);
            req.tid              = '0;
            req.tdest            = '0;
            req.tuser            = '0;
            req.is_packet_level  = 1'b0;

            wait_for_valid_slot();
            send_request(req);
            wait_for_item_done();
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// Packet-Level Configuration Sequence
// -----------------------------------------------------------------------------
// Sends the entire model configuration as one packet-level transaction. The
// driver will assert TLAST automatically on the final beat.
class bnn_fcc_config_packet_sequence extends bnn_fcc_config_base_sequence;
    `uvm_object_utils(bnn_fcc_config_packet_sequence)

    function new(string name = "bnn_fcc_config_packet_sequence");
        super.new(name);
        is_packet_level = 1'b1;
    endfunction

    virtual task body();
        load_sequence_config();

        req = cfg_axi_item_t::type_id::create("cfg_req");
        wait_for_grant();

        req.tdata = new[config_bus_data_stream.size()];
        req.tstrb = new[config_bus_keep_stream.size()];
        req.tkeep = new[config_bus_keep_stream.size()];

        foreach (config_bus_data_stream[i]) begin
            req.tdata[i] = config_bus_data_stream[i];
            req.tstrb[i] = config_bus_keep_stream[i];
            req.tkeep[i] = config_bus_keep_stream[i];
        end

        req.tlast           = 1'bX;
        req.tid             = '0;
        req.tdest           = '0;
        req.tuser           = '0;
        req.is_packet_level = 1'b1;

        send_request(req);
        wait_for_item_done();
    endtask
endclass


// -----------------------------------------------------------------------------
// Base Image Sequence
// -----------------------------------------------------------------------------
// Builds the same image stream as the original non-UVM testbench. For the
// default MNIST flow, images come from the hex file. For custom-topology runs,
// the sequence generates random images sized to the provided model.
virtual class bnn_fcc_image_base_sequence extends
    uvm_sequence #(axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH));
    `uvm_object_utils(bnn_fcc_image_base_sequence)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) in_axi_item_t;

    localparam int INPUTS_PER_BEAT = bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH / bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH;
    localparam int BYTES_PER_INPUT = bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH / 8;

    int    num_test_images;
    string base_dir;
    bit    use_custom_topology;
    bit    is_packet_level;
    real   valid_probability;

    BNN_FCC_Model    #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model;
    BNN_FCC_Stimulus #(bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH) stim;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH) in_vif;

    function new(string name = "bnn_fcc_image_base_sequence");
        super.new(name);
    endfunction

    // Returns 1 with probability p, mirroring the helper in bnn_fcc_tb.
    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0)
            `uvm_fatal("BAD_VALID_PROB",
                       $sformatf("Input valid probability must be in [0.0, 1.0], got %0f.", p))

        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    // Pull the runtime knobs from config_db and create the image database.
    function void load_sequence_config();
        string input_path;

        if (!uvm_config_db#(int)::get(null, "", "num_test_images", num_test_images))
            `uvm_fatal("NO_NUM_IMAGES", "num_test_images not specified for image sequence.")

        if (!uvm_config_db#(string)::get(null, "", "base_dir", base_dir))
            `uvm_fatal("NO_BASE_DIR", "base_dir not specified for image sequence.")

        if (!uvm_config_db#(bit)::get(null, "", "use_custom_topology", use_custom_topology))
            use_custom_topology = 1'b0;

        if (!uvm_config_db#(real)::get(null, "", "data_in_valid_probability", valid_probability))
            valid_probability = 1.0;

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH))::get(
                null, "", "in_vif", in_vif
            ))
            `uvm_fatal("NO_IN_VIF", "Image sequence could not find in_vif.")

        if (!uvm_config_db#(BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(null, "", "model_h", model))
            `uvm_fatal("NO_MODEL", "Image sequence could not find shared model_h.")

        if (!model.is_loaded)
            `uvm_fatal("MODEL_NOT_LOADED", "Image sequence received an unloaded model handle.")

        stim = new(model.topology[0]);

        if (use_custom_topology) begin
            stim.generate_random_vectors(num_test_images);
        end
        else begin
            input_path = $sformatf("%s/%s", base_dir, "test_vectors/inputs.hex");
            stim.load_from_file(input_path, num_test_images);
        end
    endfunction

    // Wait for a cycle where the producer is allowed to assert TVALID.
    task automatic wait_for_valid_slot();
        while (!chance(valid_probability))
            @(posedge in_vif.aclk iff in_vif.tready);
    endtask

    // Pack one image into the AXI beat layout used by the original testbench.
    function void pack_image(
        input  bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[],
        output bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH-1:0]  packed_data[],
        output bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH/8-1:0] packed_keep[]
    );
        int num_beats;
        int base_idx;

        num_beats = (current_img.size() + INPUTS_PER_BEAT - 1) / INPUTS_PER_BEAT;
        packed_data = new[num_beats];
        packed_keep = new[num_beats];

        for (int beat_idx = 0; beat_idx < num_beats; beat_idx++) begin
            packed_data[beat_idx] = '0;
            packed_keep[beat_idx] = '0;
            base_idx = beat_idx * INPUTS_PER_BEAT;

            // Pack pixels into the AXI beat and clear keep on unused tail bytes.
            for (int elem_idx = 0; elem_idx < INPUTS_PER_BEAT; elem_idx++) begin
                if (base_idx + elem_idx < current_img.size()) begin
                    packed_data[beat_idx][elem_idx*bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH +:
                                          bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH] = current_img[base_idx + elem_idx];
                    packed_keep[beat_idx][elem_idx*BYTES_PER_INPUT +: BYTES_PER_INPUT] = '1;
                end
            end
        end
    endfunction
endclass


// -----------------------------------------------------------------------------
// Beat-Level Image Sequence
// -----------------------------------------------------------------------------
// Sends each image as a sequence of individual AXI beats. TLAST is asserted on
// the final beat of every image.
class bnn_fcc_image_beat_sequence extends bnn_fcc_image_base_sequence;
    `uvm_object_utils(bnn_fcc_image_beat_sequence)

    function new(string name = "bnn_fcc_image_beat_sequence");
        super.new(name);
        is_packet_level = 1'b0;
    endfunction

    virtual task body();
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH-1:0] packed_data[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH/8-1:0] packed_keep[];
        int count;

        load_sequence_config();
        count = 0;

        for (int image_idx = 0; image_idx < num_test_images; image_idx++) begin
            stim.get_vector(image_idx, current_img);
            pack_image(current_img, packed_data, packed_keep);

            foreach (packed_data[beat_idx]) begin
                req = in_axi_item_t::type_id::create($sformatf("img_req%0d", count++));
                wait_for_grant();

                req.tdata = new[1];
                req.tstrb = new[1];
                req.tkeep = new[1];

                req.tdata[0]         = packed_data[beat_idx];
                req.tstrb[0]         = packed_keep[beat_idx];
                req.tkeep[0]         = packed_keep[beat_idx];
                req.tlast            = (beat_idx == packed_data.size() - 1);
                req.tid              = '0;
                req.tdest            = '0;
                req.tuser            = '0;
                req.is_packet_level  = 1'b0;

                wait_for_valid_slot();
                send_request(req);
                wait_for_item_done();
            end
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// Packet-Level Image Sequence
// -----------------------------------------------------------------------------
// Sends one packet-level AXI item per image. The driver sets TLAST on the last
// beat of the packet automatically.
class bnn_fcc_image_packet_sequence extends bnn_fcc_image_base_sequence;
    `uvm_object_utils(bnn_fcc_image_packet_sequence)

    function new(string name = "bnn_fcc_image_packet_sequence");
        super.new(name);
        is_packet_level = 1'b1;
    endfunction

    virtual task body();
        bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] current_img[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH-1:0] packed_data[];
        bit [bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH/8-1:0] packed_keep[];

        load_sequence_config();

        for (int image_idx = 0; image_idx < num_test_images; image_idx++) begin
            stim.get_vector(image_idx, current_img);
            pack_image(current_img, packed_data, packed_keep);

            req = in_axi_item_t::type_id::create($sformatf("img_req%0d", image_idx));
            wait_for_grant();

            req.tdata = new[packed_data.size()];
            req.tstrb = new[packed_keep.size()];
            req.tkeep = new[packed_keep.size()];

            foreach (packed_data[beat_idx]) begin
                req.tdata[beat_idx] = packed_data[beat_idx];
                req.tstrb[beat_idx] = packed_keep[beat_idx];
                req.tkeep[beat_idx] = packed_keep[beat_idx];
            end

            req.tlast           = 1'bX;
            req.tid             = '0;
            req.tdest           = '0;
            req.tuser           = '0;
            req.is_packet_level = 1'b1;

            send_request(req);
            wait_for_item_done();
        end
    endtask
endclass

`endif
