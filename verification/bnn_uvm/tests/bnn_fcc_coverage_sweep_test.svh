// Pawin Ruangkanit
// University of Florida
//
// Single-run coverage sweep that serializes the repo's directed UVM scenarios
// into one simulation so external grading scripts can evaluate coverage from
// one top-level testbench without merging multiple UCDBs.

`ifndef _BNN_FCC_COVERAGE_SWEEP_TEST_SVH_
`define _BNN_FCC_COVERAGE_SWEEP_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_coverage_sweep_test extends bnn_fcc_reconfig_base_test;
    `uvm_component_utils(bnn_fcc_coverage_sweep_test)

    typedef bit [bnn_fcc_uvm_pkg::INPUT_DATA_WIDTH-1:0] pixel_t;
    typedef pixel_t image_t[];

    localparam int SWEEP_TIMEOUT_IMAGES = 50;
    localparam int INPUT_STRESS_IMAGES = 120;

    function new(string name = "bnn_fcc_coverage_sweep_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Keep the small inter-packet delay used by the dedicated input-stress
        // test so the one-shot sweep still exercises image spacing coverage.
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_min_driver_delay", 2);
        uvm_config_db#(int)::set(uvm_root::get(), "*", "in_max_driver_delay", 3);
        super.build_phase(phase);
    endfunction

    protected function automatic int sparse_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 10)
            return 1;
        return fan_in / 10;
    endfunction

    protected function automatic int threshold_low_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 4)
            return 1;
        return fan_in / 4;
    endfunction

    protected function automatic int threshold_mid_target(input int fan_in);
        if (fan_in <= 0)
            return 0;
        if (fan_in < 2)
            return 1;
        return fan_in / 2;
    endfunction

    protected function automatic int choose_extreme_threshold(input int idx);
        case (idx % 8)
            0: return -2000000000;
            1: return -1400000000;
            2: return  -800000000;
            3: return          -1;
            4: return           0;
            5: return   700000000;
            6: return  1400000000;
            default: return 2000000000;
        endcase
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

    protected function void apply_density_extremes_to_model(
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model_h
    );
        foreach (model_h.weight[layer_idx]) begin
            int fan_in;
            int n_neurons;

            fan_in = model_h.topology[layer_idx];
            n_neurons = model_h.weight[layer_idx].size();

            for (int neuron_idx = 0; neuron_idx < n_neurons; neuron_idx++) begin
                int target_ones;

                case ((layer_idx + neuron_idx) % 5)
                    0: target_ones = 0;
                    1: target_ones = sparse_target(fan_in);
                    2: target_ones = fan_in / 2;
                    3: target_ones = fan_in - sparse_target(fan_in);
                    default: target_ones = fan_in;
                endcase

                for (int bit_idx = 0; bit_idx < fan_in; bit_idx++)
                    model_h.weight[layer_idx][neuron_idx][bit_idx] = (bit_idx < target_ones);

                if (layer_idx < model_h.num_layers - 1) begin
                    case ((layer_idx + neuron_idx) % 4)
                        0: model_h.threshold[layer_idx][neuron_idx] = 0;
                        1: model_h.threshold[layer_idx][neuron_idx] = threshold_low_target(fan_in);
                        2: model_h.threshold[layer_idx][neuron_idx] = threshold_mid_target(fan_in);
                        default: model_h.threshold[layer_idx][neuron_idx] = fan_in + 8;
                    endcase
                end
                else begin
                    model_h.threshold[layer_idx][neuron_idx] = 0;
                end
            end
        end

        model_h.outputs_valid = 1'b0;
        model_h.layer_outputs = new[0];
        model_h.last_input = new[0];
    endfunction

    protected function void apply_threshold_abs_extremes_to_model(
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) model_h
    );
        for (int layer_idx = 0; layer_idx < model_h.num_layers - 1; layer_idx++) begin
            for (int neuron_idx = 0; neuron_idx < model_h.threshold[layer_idx].size(); neuron_idx++)
                model_h.threshold[layer_idx][neuron_idx] =
                    choose_extreme_threshold(layer_idx * model_h.threshold[layer_idx].size() + neuron_idx);
        end

        model_h.outputs_valid = 1'b0;
        model_h.layer_outputs = new[0];
        model_h.last_input = new[0];
    endfunction

    protected task wait_for_output_handshake();
        @(posedge env.out_vif.aclk iff (env.out_vif.tvalid && env.out_vif.tready));
    endtask

    protected task run_full_packet_cfg(
        input string seq_name,
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) source_model,
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model,
        input string tag
    );
        bnn_fcc_config_packet_sequence cfg_seq;

        publish_model_handle(source_model);
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create(seq_name);
        run_config_sequence(cfg_seq, expected_model, tag);
    endtask

    protected task run_full_beat_cfg(
        input string seq_name,
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) source_model,
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model,
        input string tag
    );
        bnn_fcc_config_beat_sequence cfg_seq;

        publish_model_handle(source_model);
        cfg_seq = bnn_fcc_config_beat_sequence::type_id::create(seq_name);
        run_config_sequence(cfg_seq, expected_model, tag);
    endtask

    protected task run_beat_image_phase(input string seq_name, input int count);
        bnn_fcc_image_beat_sequence img_seq;
        int expected_total;

        expected_total = env.scoreboard.passed + env.scoreboard.failed + count;
        set_runtime_num_images(count);
        img_seq = bnn_fcc_image_beat_sequence::type_id::create(seq_name);
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_packet_image_phase(input string seq_name, input int count);
        bnn_fcc_image_packet_sequence img_seq;
        int expected_total;

        expected_total = env.scoreboard.passed + env.scoreboard.failed + count;
        set_runtime_num_images(count);
        img_seq = bnn_fcc_image_packet_sequence::type_id::create(seq_name);
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_input_tkeep_phase(input string seq_name, input int count);
        bnn_fcc_image_tkeep_packet_sequence img_seq;
        int expected_total;

        expected_total = env.scoreboard.passed + env.scoreboard.failed + count;
        set_runtime_num_images(count);
        img_seq = bnn_fcc_image_tkeep_packet_sequence::type_id::create(seq_name);
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_scripted_packet_phase(
        input string seq_name,
        ref int image_indices[$]
    );
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int expected_total;

        expected_total = env.scoreboard.passed + env.scoreboard.failed + image_indices.size();
        set_runtime_num_images(image_indices.size());
        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create(seq_name);
        img_seq.set_indices(image_indices);
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_pixel_value_phase();
        bnn_fcc_image_scripted_values_packet_sequence img_seq;
        int expected_total;

        expected_total = env.scoreboard.passed + env.scoreboard.failed + 3;
        set_runtime_num_images(3);
        img_seq = bnn_fcc_image_scripted_values_packet_sequence::type_id::create("pixel_value_img_seq");
        img_seq.append_image(build_constant_image(8'd0));
        img_seq.append_image(build_constant_image(8'd255));
        img_seq.append_image(build_extremes_mix_image());
        img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_output_directed_phase(
        input string cfg_name,
        input string img_name,
        input string tag,
        ref int image_indices[$],
        input bit class8_backpressure = 1'b0
    );
        bnn_fcc_image_scripted_packet_sequence img_seq;
        int expected_total;

        run_full_packet_cfg(cfg_name, model, model, tag);
        expected_total = env.scoreboard.passed + env.scoreboard.failed + image_indices.size();
        set_runtime_num_images(image_indices.size());
        img_seq = bnn_fcc_image_scripted_packet_sequence::type_id::create(img_name);
        img_seq.set_indices(image_indices);

        if (!class8_backpressure) begin
            img_seq.start(env.in_agent.sequencer);
        end
        else begin
            fork
                begin
                    ctrl_vif.force_output_ready(1'b1);
                    wait_for_output_handshake();
                    @(posedge env.out_vif.aclk);
                    ctrl_vif.release_output_ready();

                    wait (env.out_vif.tvalid == 1'b1);
                    ctrl_vif.force_output_ready(1'b0);
                    repeat (6) @(posedge env.out_vif.aclk);
                    ctrl_vif.force_output_ready(1'b1);
                    wait_for_output_handshake();
                    @(posedge env.out_vif.aclk);
                    ctrl_vif.release_output_ready();
                end
                begin
                    img_seq.start(env.in_agent.sequencer);
                end
            join
        end

        wait_for_scoreboard_total(expected_total);
    endtask

    protected task run_single_beat_scenario();
        `uvm_info(get_type_name(), "Coverage sweep: single-beat baseline scenario.", UVM_LOW)
        run_full_beat_cfg("sweep_single_beat_cfg", model, model, "coverage sweep single-beat full configuration");
        run_beat_image_phase("sweep_single_beat_img", num_test_images);
    endtask

    protected task run_tkeep_scenarios();
        bnn_fcc_config_tkeep_packet_sequence cfg_tkeep_seq;

        `uvm_info(get_type_name(), "Coverage sweep: TKEEP scenarios.", UVM_LOW)

        run_full_packet_cfg("sweep_input_tkeep_cfg", model, model, "coverage sweep input-tkeep full configuration");
        run_input_tkeep_phase("sweep_input_tkeep_img", num_test_images);

        publish_model_handle(model);
        cfg_tkeep_seq = bnn_fcc_config_tkeep_packet_sequence::type_id::create("sweep_cfg_tkeep_seq");
        run_config_sequence(cfg_tkeep_seq, model, "coverage sweep full config with contiguous partial TKEEP");
        run_input_tkeep_phase("sweep_dual_tkeep_img", num_test_images);
    endtask

    protected task run_output_directed_scenarios();
        int image_indices[$];

        `uvm_info(get_type_name(), "Coverage sweep: directed output scenarios.", UVM_LOW)

        image_indices.delete();
        for (int i = 0; i < 12; i++)
            image_indices.push_back(3);
        image_indices.push_back(2);
        run_output_directed_phase("out_cfg_class0", "out_img_class0",
                                  "coverage sweep class-0 first/repeat/long-run configuration",
                                  image_indices);

        image_indices = '{2, 2, 3};
        run_output_directed_phase("out_cfg_class1", "out_img_class1",
                                  "coverage sweep class-1 first/repeat configuration",
                                  image_indices);

        image_indices = '{4, 18, 30, 0};
        run_output_directed_phase("out_cfg_class4", "out_img_class4",
                                  "coverage sweep class-4 first configuration",
                                  image_indices);

        image_indices = '{8, 0, 17, 3};
        run_output_directed_phase("out_cfg_class6", "out_img_class6",
                                  "coverage sweep class-6 first configuration",
                                  image_indices);

        image_indices = '{84, 84, 3};
        run_output_directed_phase("out_cfg_class8", "out_img_class8",
                                  "coverage sweep class-8 backpressure configuration",
                                  image_indices, 1'b1);

        image_indices = '{7, 7, 3};
        run_output_directed_phase("out_cfg_class9", "out_img_class9",
                                  "coverage sweep class-9 first/repeat configuration",
                                  image_indices);
    endtask

    protected task run_threshold_preamble_scenario();
        bnn_fcc_config_packet_sequence thresh_layer1_seq;
        bnn_fcc_config_packet_sequence weight_layer0_seq;
        bnn_fcc_config_packet_sequence thresh_layer0_seq;
        bnn_fcc_config_packet_sequence weight_layer2_seq;
        int layer_sel[$];
        int image_indices[$];

        `uvm_info(get_type_name(), "Coverage sweep: threshold preamble scenario.", UVM_LOW)

        publish_model_handle(model);

        layer_sel = '{1};
        thresh_layer1_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_thresh_layer1_seq");
        thresh_layer1_seq.include_weights = 1'b0;
        thresh_layer1_seq.include_thresholds = 1'b1;
        thresh_layer1_seq.select_layers(layer_sel);
        run_config_sequence(thresh_layer1_seq, model, "coverage sweep threshold-only preamble on layer 1");

        layer_sel = '{0};
        weight_layer0_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_weight_layer0_seq");
        weight_layer0_seq.include_weights = 1'b1;
        weight_layer0_seq.include_thresholds = 1'b0;
        weight_layer0_seq.select_layers(layer_sel);
        run_config_sequence(weight_layer0_seq, model, "coverage sweep weights-only preamble on layer 0");

        thresh_layer0_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_thresh_layer0_seq");
        thresh_layer0_seq.include_weights = 1'b0;
        thresh_layer0_seq.include_thresholds = 1'b1;
        thresh_layer0_seq.select_layers(layer_sel);
        run_config_sequence(thresh_layer0_seq, model, "coverage sweep threshold-only preamble on layer 0");

        layer_sel = '{model.num_layers - 1};
        weight_layer2_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_weight_output_seq");
        weight_layer2_seq.include_weights = 1'b1;
        weight_layer2_seq.include_thresholds = 1'b0;
        weight_layer2_seq.select_layers(layer_sel);
        run_config_sequence(weight_layer2_seq, model, "coverage sweep weights-only preamble on output layer");

        run_full_packet_cfg("sweep_thresh_preamble_full_cfg", model, model,
                            "coverage sweep final full configuration after threshold preamble");

        image_indices = '{15, 15, 7};
        run_scripted_packet_phase("sweep_thresh_preamble_img", image_indices);
    endtask

    protected task run_config_order_scenario();
        bnn_fcc_config_packet_sequence cfg_seq;
        int layer_sel[$];

        `uvm_info(get_type_name(), "Coverage sweep: config-order scenario.", UVM_LOW)

        publish_model_handle(model);

        layer_sel = '{0};
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_cfg_order_w0a");
        cfg_seq.include_weights = 1'b1;
        cfg_seq.include_thresholds = 1'b0;
        cfg_seq.select_layers(layer_sel);
        run_config_sequence(cfg_seq, model, "coverage sweep weights-only layer 0 preamble");

        layer_sel = '{1};
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_cfg_order_t1");
        cfg_seq.include_weights = 1'b0;
        cfg_seq.include_thresholds = 1'b1;
        cfg_seq.select_layers(layer_sel);
        run_config_sequence(cfg_seq, model, "coverage sweep threshold-only layer 1 preamble");

        layer_sel = '{0};
        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_cfg_order_w0b");
        cfg_seq.include_weights = 1'b1;
        cfg_seq.include_thresholds = 1'b0;
        cfg_seq.select_layers(layer_sel);
        run_config_sequence(cfg_seq, model, "coverage sweep weights-only layer 0 revisit");

        cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_cfg_order_w0c");
        cfg_seq.include_weights = 1'b1;
        cfg_seq.include_thresholds = 1'b0;
        cfg_seq.select_layers(layer_sel);
        run_config_sequence(cfg_seq, model, "coverage sweep weights-only layer 0 repeat");

        run_full_packet_cfg("sweep_cfg_order_full_cfg", model, model,
                            "coverage sweep final full configuration after config-order scenario");
        repeat (10) @(posedge env.cfg_vif.aclk);
    endtask

    protected task run_threshold_abs_scenario();
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) extreme_model;

        `uvm_info(get_type_name(), "Coverage sweep: threshold-absolute extremes scenario.", UVM_LOW)

        extreme_model = model.clone();
        apply_threshold_abs_extremes_to_model(extreme_model);
        run_full_packet_cfg("sweep_thresh_abs_cfg", extreme_model, extreme_model,
                            "coverage sweep threshold-absolute extremes configuration");
        repeat (5) @(posedge env.in_vif.aclk);
    endtask

    protected task run_density_extremes_scenario();
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) dense_model;
        int image_indices[$];

        `uvm_info(get_type_name(), "Coverage sweep: density-extremes scenario.", UVM_LOW)

        dense_model = model.clone();
        apply_density_extremes_to_model(dense_model);
        run_full_packet_cfg("sweep_density_cfg", dense_model, dense_model,
                            "coverage sweep density-extremes full configuration");

        image_indices.delete();
        for (int i = 0; i < 12; i++)
            image_indices.push_back(3);
        image_indices.push_back(1);
        run_scripted_packet_phase("sweep_density_img", image_indices);
    endtask

    protected task run_pixel_value_scenario();
        `uvm_info(get_type_name(), "Coverage sweep: directed pixel-value scenario.", UVM_LOW)
        run_full_packet_cfg("sweep_pixel_cfg", model, model,
                            "coverage sweep pixel-values full configuration");
        run_pixel_value_phase();
    endtask

    protected task run_input_stress_scenario();
        int image_indices[$];

        `uvm_info(get_type_name(), "Coverage sweep: input-stress scenario.", UVM_LOW)

        run_full_packet_cfg("sweep_input_stress_cfg", model, model,
                            "coverage sweep input-stress full configuration");

        image_indices.push_back(18);
        for (int i = 1; i < INPUT_STRESS_IMAGES; i++)
            image_indices.push_back((i - 1) % 100);
        run_scripted_packet_phase("sweep_input_stress_img", image_indices);
    endtask

    protected task run_weights_only_reconfig_scenario();
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model;
        bnn_fcc_config_beat_sequence re_cfg_seq;
        int touched_layers[$];

        `uvm_info(get_type_name(), "Coverage sweep: weights-only reconfiguration scenario.", UVM_LOW)

        run_full_beat_cfg("sweep_weights_init_cfg", model, model,
                          "coverage sweep initial full configuration before weights-only reconfig");
        run_beat_image_phase("sweep_weights_pre_img", 4);

        rand_model = make_random_model_like(model);
        expected_model = model.clone();
        expected_model.update_layers_from(rand_model, touched_layers, 1'b1, 1'b0);

        publish_model_handle(rand_model);
        re_cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("sweep_weights_re_cfg");
        re_cfg_seq.include_weights = 1'b1;
        re_cfg_seq.include_thresholds = 1'b0;
        re_cfg_seq.order_mode = bnn_fcc_uvm_pkg::BNN_CFG_ORDER_WEIGHTS_THEN_THRESH;
        run_config_sequence(re_cfg_seq, expected_model, "coverage sweep weights-only reconfiguration");

        publish_model_handle(expected_model);
        run_beat_image_phase("sweep_weights_post_img", 4);
    endtask

    protected task run_thresh_only_reconfig_scenario();
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model;
        bnn_fcc_config_packet_sequence re_cfg_seq;
        int threshold_layers[$];

        `uvm_info(get_type_name(), "Coverage sweep: thresholds-only reconfiguration scenario.", UVM_LOW)

        run_full_packet_cfg("sweep_thresh_only_init_cfg", model, model,
                            "coverage sweep initial full configuration before thresholds-only reconfig");
        run_beat_image_phase("sweep_thresh_only_pre_img", 4);

        build_hidden_layer_list(threshold_layers);
        if (threshold_layers.size() == 0)
            `uvm_fatal("NO_THRESH_LAYERS",
                       "Coverage sweep thresholds-only scenario requires at least one hidden layer.")

        rand_model = make_random_model_like(model);
        expected_model = model.clone();
        expected_model.update_layers_from(rand_model, threshold_layers, 1'b0, 1'b1);

        publish_model_handle(rand_model);
        re_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_thresh_only_re_cfg");
        re_cfg_seq.include_weights = 1'b0;
        re_cfg_seq.include_thresholds = 1'b1;
        re_cfg_seq.order_mode = bnn_fcc_uvm_pkg::BNN_CFG_ORDER_THRESH_THEN_WEIGHTS;
        re_cfg_seq.select_layers(threshold_layers);
        run_config_sequence(re_cfg_seq, expected_model, "coverage sweep thresholds-only reconfiguration");

        publish_model_handle(expected_model);
        run_beat_image_phase("sweep_thresh_only_post_img", 4);
    endtask

    protected task run_partial_reconfig_scenario();
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) rand_model;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) expected_model;
        bnn_fcc_config_packet_sequence re_cfg_seq;
        int selected_layers[$];

        `uvm_info(get_type_name(), "Coverage sweep: partial-layer reconfiguration scenario.", UVM_LOW)

        run_full_packet_cfg("sweep_partial_init_cfg", model, model,
                            "coverage sweep initial full configuration before partial reconfig");
        run_packet_image_phase("sweep_partial_pre_img", 3);

        selected_layers.push_back(0);
        if (model.num_layers > 1)
            selected_layers.push_back(model.num_layers - 1);

        rand_model = make_random_model_like(model);
        expected_model = model.clone();
        expected_model.update_layers_from(rand_model, selected_layers, 1'b1, 1'b1);

        publish_model_handle(rand_model);
        re_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_partial_re_cfg");
        re_cfg_seq.include_weights = 1'b1;
        re_cfg_seq.include_thresholds = 1'b1;
        re_cfg_seq.order_mode = bnn_fcc_uvm_pkg::BNN_CFG_ORDER_THRESH_THEN_WEIGHTS;
        re_cfg_seq.select_layers(selected_layers);
        run_config_sequence(re_cfg_seq, expected_model, "coverage sweep partial-layer reconfiguration");

        publish_model_handle(expected_model);
        run_packet_image_phase("sweep_partial_post_img", 5);
    endtask

    protected task run_reset_bins_scenario();
        int few_images[$];
        int some_images[$];
        int many_images[$];

        `uvm_info(get_type_name(), "Coverage sweep: reset-bin accumulation scenario.", UVM_LOW)

        run_full_packet_cfg("sweep_reset_bins_cfg0", model, model,
                            "coverage sweep initial full configuration before zero-workload reset");
        pulse_reset(5, 1'b1);

        run_full_packet_cfg("sweep_reset_bins_cfg1", model, model,
                            "coverage sweep same full configuration before few-workload reset");
        few_images = '{18, 30, 0};
        run_scripted_packet_phase("sweep_reset_bins_few_img", few_images);
        pulse_reset(5, 1'b1);

        run_full_packet_cfg("sweep_reset_bins_cfg2", model, model,
                            "coverage sweep same full configuration before some-workload reset");
        for (int i = 0; i < 8; i++)
            some_images.push_back(i);
        run_scripted_packet_phase("sweep_reset_bins_some_img", some_images);
        pulse_reset(5, 1'b1);

        run_full_packet_cfg("sweep_reset_bins_cfg3", model, model,
                            "coverage sweep same full configuration before many-workload reset");
        for (int i = 0; i < 24; i++)
            many_images.push_back(i % 100);
        run_scripted_packet_phase("sweep_reset_bins_many_img", many_images);
        pulse_reset(5, 1'b1);
    endtask

    protected task run_reset_reconfig_scenario();
        bnn_fcc_config_beat_sequence init_cfg_seq;
        bnn_fcc_config_packet_sequence post_reset_cfg_seq;
        bnn_fcc_image_packet_sequence pre_img_seq;
        bnn_fcc_image_packet_sequence post_img_seq;
        BNN_FCC_Model #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) post_reset_model;
        int scoreboard_total_before_reset;
        int wait_cycles;

        `uvm_info(get_type_name(), "Coverage sweep: reset-then-reconfigure scenario.", UVM_LOW)

        publish_model_handle(model);
        init_cfg_seq = bnn_fcc_config_beat_sequence::type_id::create("sweep_reset_reconfig_init_cfg");
        run_config_sequence(init_cfg_seq, model, "coverage sweep initial full configuration before reset-reconfig");

        set_runtime_num_images(6);
        pre_img_seq = bnn_fcc_image_packet_sequence::type_id::create("sweep_reset_reconfig_pre_img");
        pre_img_seq.start(env.in_agent.sequencer);

        wait_cycles = 0;
        while ((wait_cycles < 50) && !env.out_vif.tvalid) begin
            @(posedge env.out_vif.aclk);
            wait_cycles++;
        end

        scoreboard_total_before_reset = env.scoreboard.passed + env.scoreboard.failed;
        pulse_reset(5, 1'b0);

        post_reset_model = make_random_model_like(model);
        publish_model_handle(post_reset_model);

        post_reset_cfg_seq = bnn_fcc_config_packet_sequence::type_id::create("sweep_reset_reconfig_post_cfg");
        run_config_sequence(post_reset_cfg_seq, post_reset_model, "coverage sweep post-reset full reconfiguration");

        set_runtime_num_images(4);
        post_img_seq = bnn_fcc_image_packet_sequence::type_id::create("sweep_reset_reconfig_post_img");
        post_img_seq.start(env.in_agent.sequencer);
        wait_for_scoreboard_total(scoreboard_total_before_reset + 4);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(),
                  "Starting single-run coverage sweep test.",
                  UVM_LOW)

        if (verify_model && !use_custom_topology)
            verify_reference_model();

        run_single_beat_scenario();
        run_tkeep_scenarios();
        run_output_directed_scenarios();
        run_threshold_preamble_scenario();
        run_config_order_scenario();
        run_threshold_abs_scenario();
        run_density_extremes_scenario();
        run_pixel_value_scenario();
        run_input_stress_scenario();
        run_weights_only_reconfig_scenario();
        run_thresh_only_reconfig_scenario();
        run_partial_reconfig_scenario();
        run_reset_bins_scenario();
        run_reset_reconfig_scenario();

        set_runtime_num_images(num_test_images);
        publish_model_handle(model);
        ctrl_vif.release_output_ready();

        phase.drop_objection(this);
    endtask
endclass

`endif
