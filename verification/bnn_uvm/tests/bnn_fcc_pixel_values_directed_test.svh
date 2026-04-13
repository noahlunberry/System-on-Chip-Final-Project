// Greg Stitt
// University of Florida
//
// Coverage-directed test that sends exact pixel-value patterns rather than
// dataset indices so input coverage can observe deliberate low/mid/high/max
// byte values under a normal configured model.

`ifndef _BNN_FCC_PIXEL_VALUES_DIRECTED_TEST_SVH_
`define _BNN_FCC_PIXEL_VALUES_DIRECTED_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_pixel_values_directed_test extends bnn_fcc_base_test;
    `uvm_component_utils(bnn_fcc_pixel_values_directed_test)

    typedef bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] pixel_t;
    typedef pixel_t image_t[];

    function new(string name = "bnn_fcc_pixel_values_directed_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected function automatic image_t build_constant_image(input pixel_t value);
        image_t img;

        img = new[model.topology[0]];
        foreach (img[i])
            img[i] = value;

        return img;
    endfunction

    protected function automatic image_t build_extremes_mix_image();
        image_t img;

        img = new[model.topology[0]];
        foreach (img[i]) begin
            case (i % 9)
                0: img[i] = 8'd0;
                1: img[i] = 8'd1;
                2: img[i] = 8'd63;
                3: img[i] = 8'd64;
                4: img[i] = 8'd128;
                5: img[i] = 8'd191;
                6: img[i] = 8'd192;
                7: img[i] = 8'd254;
                default: img[i] = 8'd255;
            endcase
        end

        return img;
    endfunction

    task run_phase(uvm_phase phase);
        bnn_fcc_config_packet_sequence cfg_seq;
        bnn_fcc_image_scripted_values_packet_sequence img_seq;
        int expected_outputs;

        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting directed pixel-value coverage test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("cfg_seq");
        run_config_sequence(cfg_seq, model, "pixel-values full configuration");

        img_seq = bnn_fcc_image_scripted_values_packet_sequence::type_id::create("img_seq");
        img_seq.append_image(build_constant_image(8'd0));
        img_seq.append_image(build_constant_image(8'd255));
        img_seq.append_image(build_extremes_mix_image());

        expected_outputs = 3;
        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", expected_outputs);

        img_seq.start(env.in_agent.sequencer);
        wait ((env.scoreboard.passed + env.scoreboard.failed) == expected_outputs);
        repeat (5) @(posedge env.in_vif.aclk);

        uvm_config_db#(int)::set(uvm_root::get(), "*", "num_test_images", num_test_images);

        phase.drop_objection(this);
    endtask
endclass

`endif
