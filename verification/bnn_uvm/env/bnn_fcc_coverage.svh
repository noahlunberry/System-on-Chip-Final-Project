// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// COVERAGE: bnn_fcc_coverage
// Maps to: coverage_plan.txt (ALL 5 categories) & IMPLEMENTATION_PLAN.md §"Mapping FCC coverage"
//
// DESCRIPTION:
// Comprehensive coverage collector implementing covergroups for every category
// in coverage_plan.txt. Each covergroup is traced back to the specific coverage
// plan category and the report's mapping table row.
//
// CATEGORY 1: AXI4-Stream Protocol Patterns  -> cg_cfg_handshake, cg_in_handshake, cg_out_backpressure
// CATEGORY 2: Configuration Data Diversity   -> cg_cfg_content, cg_weight_density, cg_thresh
// CATEGORY 3: Computational Stimulus         -> cg_outputs, cg_output_patterns
// CATEGORY 4: Configuration-Image Sequencing -> cg_reconfig
// CATEGORY 5: Reset Scenarios                -> cg_reset

`ifndef _BNN_FCC_COVERAGE_SVH_
`define _BNN_FCC_COVERAGE_SVH_

class bnn_fcc_coverage extends uvm_component;
    `uvm_component_utils(bnn_fcc_coverage)

    // =========================================================================
    // TLM connections (wired from env connect_phase)
    // =========================================================================
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(64)) cfg_fifo;
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(64)) in_fifo;
    uvm_tlm_analysis_fifo #(axi4_stream_seq_item #(8))  out_fifo;

    // Analysis exports for env wiring
    uvm_analysis_export #(axi4_stream_seq_item #(64)) cfg_ae;
    uvm_analysis_export #(axi4_stream_seq_item #(64)) in_ae;
    uvm_analysis_export #(axi4_stream_seq_item #(8))  out_ae;

    // =========================================================================
    // Virtual interfaces for cycle-level coverage sampling
    // Maps to: filter_coverage.svh pattern (interface_coverage sampled @posedge)
    // =========================================================================
    virtual axi4_stream_if #(64) cfg_vif;
    virtual axi4_stream_if #(64) in_vif;
    virtual axi4_stream_if #(8)  out_vif;

    // =========================================================================
    // CATEGORY 1: AXI4-Stream Protocol Patterns (coverage_plan.txt lines 10-29)
    // Maps to: IMPLEMENTATION_PLAN.md table rows 1-7
    // =========================================================================

    // --- Config interface handshake coverage ---
    // "Vary how you assert TVALID (continuous vs. intermittent vs. bursts)"
    int unsigned cfg_gap_len;      // cycles between valid assertions
    int unsigned cfg_burst_len;    // consecutive valid beats
    covergroup cg_cfg_handshake;
        cp_gap_len   : coverpoint cfg_gap_len   { bins zero={0}; bins short_gap={[1:3]}; bins med_gap={[4:15]}; bins long_gap={[16:$]}; }
        cp_burst_len : coverpoint cfg_burst_len  { bins one={1}; bins short_burst={[2:4]}; bins long_burst={[5:32]}; bins huge_burst={[33:$]}; }
    endgroup

    // --- Config interface valid/ready/backpressure ---
    covergroup cg_cfg_intf;
        cp_valid   : coverpoint cfg_vif.tvalid { bins hi={1}; bins lo={0}; }
        cp_ready   : coverpoint cfg_vif.tready { bins hi={1}; bins lo={0}; }
        cp_bp      : coverpoint (!cfg_vif.tready && cfg_vif.tvalid) { bins backpressure={1}; }
    endgroup

    // --- Input interface handshake coverage ---
    // "Vary TVALID patterns during image transfers"
    // "Vary timing between consecutive images"
    int unsigned in_gap_len;
    int unsigned in_burst_len;
    int unsigned inter_image_gap;
    covergroup cg_in_handshake;
        cp_gap_len        : coverpoint in_gap_len       { bins zero={0}; bins short_gap={[1:3]}; bins med_gap={[4:15]}; bins long_gap={[16:$]}; }
        cp_burst_len      : coverpoint in_burst_len      { bins one={1}; bins short_burst={[2:4]}; bins long_burst={[5:32]}; bins huge_burst={[33:$]}; }
        cp_inter_img_gap  : coverpoint inter_image_gap   { bins zero={0}; bins short_gap={[1:5]}; bins med_gap={[6:20]}; bins long_gap={[21:$]}; }
    endgroup

    // --- Input interface valid/ready/backpressure ---
    covergroup cg_in_intf;
        cp_valid   : coverpoint in_vif.tvalid { bins hi={1}; bins lo={0}; }
        cp_ready   : coverpoint in_vif.tready { bins hi={1}; bins lo={0}; }
        cp_bp      : coverpoint (!in_vif.tready && in_vif.tvalid) { bins backpressure={1}; }
    endgroup

    // --- Output interface backpressure coverage ---
    // "Vary TREADY patterns (continuous vs. intermittent vs. bursts)"
    // "Vary when TREADY asserts relative to TVALID (before/same/after)"
    // "Apply backpressure scenarios"
    int unsigned out_stall_len;
    int unsigned out_ready_burst_len;
    covergroup cg_out_backpressure;
        cp_stall_len       : coverpoint out_stall_len       { bins zero={0}; bins short_stall={[1:3]}; bins med_stall={[4:15]}; bins long_stall={[16:$]}; }
        cp_ready_burst_len : coverpoint out_ready_burst_len  { bins one={1}; bins short_burst={[2:5]}; bins long_burst={[6:$]}; }
    endgroup

    // --- Output interface valid/ready/backpressure ---
    covergroup cg_out_intf;
        cp_valid   : coverpoint out_vif.tvalid { bins hi={1}; bins lo={0}; }
        cp_ready   : coverpoint out_vif.tready { bins hi={1}; bins lo={0}; }
        cp_bp      : coverpoint (!out_vif.tready && out_vif.tvalid) { bins backpressure={1}; option.at_least = 10; }
    endgroup

    // =========================================================================
    // CATEGORY 2: Configuration Data Diversity (coverage_plan.txt lines 32-43)
    // Maps to: IMPLEMENTATION_PLAN.md table rows 8-11
    // =========================================================================

    // --- Config message content ---
    // "Vary the ordering of weight/threshold messages"
    // "Vary the order in which layers are configured"
    bit          cfg_msg_type;     // 0=weights, 1=thresholds
    int unsigned cfg_layer_id;
    int unsigned cfg_msg_order;    // ordinal position in config stream
    covergroup cg_cfg_content;
        cp_msg_type  : coverpoint cfg_msg_type  { bins weights={0}; bins thresholds={1}; }
        cp_layer_id  : coverpoint cfg_layer_id   { bins layer[] = {[0:3]}; }
        cp_order     : coverpoint cfg_msg_order  { bins first={0}; bins mid={[1:3]}; bins last={[4:$]}; }
        x_msg_layer  : cross cp_msg_type, cp_layer_id;
    endgroup

    // --- Weight density coverage ---
    // "Vary the density of 1s vs 0s in neuron weight patterns"
    // "Include extreme cases and various intermediate densities"
    int unsigned weight_density_pct; // 0-100
    int unsigned weight_layer_id;
    covergroup cg_weight_density;
        cp_density : coverpoint weight_density_pct {
            bins near_zero  = {[0:5]};
            bins low        = {[6:25]};
            bins mid_low    = {[26:40]};
            bins mid        = {[41:60]};
            bins mid_high   = {[61:75]};
            bins high       = {[76:95]};
            bins near_full  = {[96:100]};
        }
        cp_layer   : coverpoint weight_layer_id { bins layer[] = {[0:3]}; }
        x_density_layer : cross cp_density, cp_layer;
    endgroup

    // --- Threshold magnitude coverage ---
    // "Use a range of threshold values (small, medium, large)"
    // "Vary threshold values across layers"
    int unsigned thresh_mag;
    int unsigned thresh_layer_id;
    covergroup cg_thresh;
        cp_mag   : coverpoint thresh_mag {
            bins small  = {[0:50]};
            bins medium = {[51:200]};
            bins large  = {[201:500]};
            bins huge   = {[501:$]};
        }
        cp_layer : coverpoint thresh_layer_id { bins layer[] = {[0:3]}; }
        x_thresh_layer : cross cp_mag, cp_layer;
    endgroup

    // =========================================================================
    // CATEGORY 3: Computational Stimulus (coverage_plan.txt lines 46-51)
    // Maps to: IMPLEMENTATION_PLAN.md table rows 11-12
    // =========================================================================

    // --- Classification output coverage ---
    // "Design inputs that produce all possible output classes"
    int out_class;
    int unsigned out_backpressure_bin; // 0=none, 1=light, 2=heavy
    covergroup cg_outputs;
        cp_class : coverpoint out_class { bins classes[] = {[0:9]}; }
        cp_bp_bin : coverpoint out_backpressure_bin { bins none={0}; bins light={1}; bins heavy={2}; }
        x_class_bp : cross cp_class, cp_bp_bin;
    endgroup

    // --- Output pattern coverage ---
    // "Test sequences with repeated vs. varying output classes"
    int unsigned repeat_run_len;
    int          last_class;
    covergroup cg_output_patterns;
        cp_repeat_len : coverpoint repeat_run_len {
            bins single = {1};
            bins short_run = {[2:3]};
            bins med_run = {[4:10]};
            bins long_run = {[11:$]};
        }
    endgroup

    // --- Workload size coverage ---
    // "Test with varying numbers of images (few to many)"
    // "Use diverse pixel values"
    int unsigned num_images_seen;
    int unsigned pixel_class;  // 0=all_zero, 1=all_ff, 2=mixed
    covergroup cg_workload;
        cp_num_images : coverpoint num_images_seen {
            bins few = {[1:5]};
            bins some = {[6:20]};
            bins many = {[21:100]};
            bins stress = {[101:$]};
        }
        cp_pixel : coverpoint pixel_class { bins all_zero={0}; bins all_ff={1}; bins mixed={2}; }
    endgroup

    // --- TKEEP coverage ---
    // "Consider partial bus transfers (TKEEP)"
    int unsigned tkeep_valid_bytes;
    bit          tkeep_is_last;
    covergroup cg_tkeep;
        cp_valid_bytes : coverpoint tkeep_valid_bytes { bins partial[] = {[1:7]}; bins full = {8}; }
        cp_is_last     : coverpoint tkeep_is_last { bins not_last={0}; bins is_last={1}; }
        x_keep_last    : cross cp_valid_bytes, cp_is_last;
    endgroup

    // =========================================================================
    // CATEGORY 4: Configuration-Image Sequencing (coverage_plan.txt lines 54-60)
    // Maps to: IMPLEMENTATION_PLAN.md table row 13
    // =========================================================================

    // --- Reconfiguration coverage ---
    // "Test full configuration (all layers)"
    // "Test partial reconfiguration (subset of layers)"
    // "Try reconfiguring weights only, thresholds only, or both"
    int unsigned reconfig_type;    // 0=full, 1=weights_only, 2=thresh_only, 3=partial_layers
    int unsigned layers_touched;
    covergroup cg_reconfig;
        cp_type   : coverpoint reconfig_type { bins full={0}; bins weights_only={1}; bins thresh_only={2}; bins partial={3}; }
        cp_layers : coverpoint layers_touched { bins one={1}; bins some={[2:3]}; bins all={[4:$]}; }
    endgroup

    // =========================================================================
    // CATEGORY 5: Reset Scenarios (coverage_plan.txt lines 63-73)
    // Maps to: IMPLEMENTATION_PLAN.md table rows 14-15
    // =========================================================================

    // --- Reset timing coverage ---
    // "Apply reset at different phases"
    // "Vary frequency and number of resets"
    int unsigned reset_phase;    // 0=idle, 1=during_config, 2=during_image, 3=during_output, 4=at_tlast
    int unsigned reset_count;
    bit          post_reset_same_cfg; // same config after reset?
    covergroup cg_reset;
        cp_phase  : coverpoint reset_phase {
            bins idle={0}; bins during_config={1}; bins during_image={2};
            bins during_output={3}; bins at_tlast={4};
        }
        cp_count  : coverpoint reset_count { bins one={1}; bins few={[2:3]}; bins many={[4:$]}; }
        x_phase_count : cross cp_phase, cp_count;
    endgroup

    // --- Post-reset behavior coverage ---
    // "Test with same vs. different configuration after reset"
    covergroup cg_reset_post;
        cp_same_cfg : coverpoint post_reset_same_cfg { bins same={1}; bins different={0}; }
    endgroup

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
        // Category 1: Protocol
        cg_cfg_handshake    = new();
        cg_cfg_intf         = new();
        cg_in_handshake     = new();
        cg_in_intf          = new();
        cg_out_backpressure = new();
        cg_out_intf         = new();
        // Category 2: Config diversity
        cg_cfg_content      = new();
        cg_weight_density   = new();
        cg_thresh           = new();
        // Category 3: Computational stimulus
        cg_outputs          = new();
        cg_output_patterns  = new();
        cg_workload         = new();
        cg_tkeep            = new();
        // Category 4: Sequencing
        cg_reconfig         = new();
        // Category 5: Reset
        cg_reset            = new();
        cg_reset_post       = new();
    endfunction

    // =========================================================================
    // Build phase
    // =========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg_fifo = new("cfg_fifo", this);
        in_fifo  = new("in_fifo", this);
        out_fifo = new("out_fifo", this);

        cfg_ae = new("cfg_ae", this);
        in_ae  = new("in_ae", this);
        out_ae = new("out_ae", this);

        // Get VIFs for cycle-level sampling
        if (!uvm_config_db#(virtual axi4_stream_if #(64))::get(this, "", "cfg_vif", cfg_vif))
            `uvm_warning("COV_NO_VIF", "Could not get cfg_vif for coverage")
        if (!uvm_config_db#(virtual axi4_stream_if #(64))::get(this, "", "in_vif", in_vif))
            `uvm_warning("COV_NO_VIF", "Could not get in_vif for coverage")
        if (!uvm_config_db#(virtual axi4_stream_if #(8))::get(this, "", "out_vif", out_vif))
            `uvm_warning("COV_NO_VIF", "Could not get out_vif for coverage")
    endfunction

    // =========================================================================
    // Connect phase
    // =========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        cfg_ae.connect(cfg_fifo.analysis_export);
        in_ae.connect(in_fifo.analysis_export);
        out_ae.connect(out_fifo.analysis_export);
    endfunction

    // =========================================================================
    // Run phase: fork multiple sampling threads
    // Maps to: filter_coverage.svh pattern (separate tasks for interface vs packet)
    // =========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            sample_cfg_interface();
            sample_in_interface();
            sample_out_interface();
            sample_out_transactions();
        join
    endtask

    // --- Cycle-level interface coverage sampling ---
    task sample_cfg_interface();
        int unsigned gap_cnt = 0;
        int unsigned burst_cnt = 0;
        bit prev_valid = 0;
        if (cfg_vif == null) return;
        forever begin
            @(posedge cfg_vif.aclk);
            cg_cfg_intf.sample();
            if (cfg_vif.tvalid && cfg_vif.tready) begin
                cfg_burst_len = burst_cnt + 1;
                cfg_gap_len = gap_cnt;
                cg_cfg_handshake.sample();
                burst_cnt++;
                gap_cnt = 0;
            end else if (cfg_vif.tvalid && !cfg_vif.tready) begin
                // waiting - don't reset burst
            end else begin
                if (burst_cnt > 0) begin
                    burst_cnt = 0;
                end
                gap_cnt++;
            end
        end
    endtask

    task sample_in_interface();
        int unsigned gap_cnt = 0;
        int unsigned burst_cnt = 0;
        if (in_vif == null) return;
        forever begin
            @(posedge in_vif.aclk);
            cg_in_intf.sample();
            if (in_vif.tvalid && in_vif.tready) begin
                in_burst_len = burst_cnt + 1;
                in_gap_len = gap_cnt;
                cg_in_handshake.sample();
                burst_cnt++;
                gap_cnt = 0;
                // Track TKEEP on input bus
                begin
                    int valid_bytes = 0;
                    for (int b = 0; b < 8; b++) begin
                        if (in_vif.tkeep[b]) valid_bytes++;
                    end
                    tkeep_valid_bytes = valid_bytes;
                    tkeep_is_last = in_vif.tlast;
                    cg_tkeep.sample();
                end
            end else begin
                if (burst_cnt > 0) burst_cnt = 0;
                gap_cnt++;
            end
        end
    endtask

    task sample_out_interface();
        int unsigned stall_cnt = 0;
        int unsigned ready_cnt = 0;
        if (out_vif == null) return;
        forever begin
            @(posedge out_vif.aclk);
            cg_out_intf.sample();
            if (out_vif.tready) begin
                ready_cnt++;
                if (stall_cnt > 0) begin
                    out_stall_len = stall_cnt;
                    cg_out_backpressure.sample();
                    stall_cnt = 0;
                end
            end else begin
                stall_cnt++;
                if (ready_cnt > 0) begin
                    out_ready_burst_len = ready_cnt;
                    cg_out_backpressure.sample();
                    ready_cnt = 0;
                end
            end
        end
    endtask

    // --- Transaction-level output coverage sampling ---
    task sample_out_transactions();
        axi4_stream_seq_item #(8) item;
        last_class = -1;
        repeat_run_len = 0;
        num_images_seen = 0;
        forever begin
            out_fifo.get(item);
            foreach (item.tdata[i]) begin
                out_class = item.tdata[i];
                num_images_seen++;

                // Determine backpressure bin from current stall state
                if (out_stall_len == 0) out_backpressure_bin = 0;
                else if (out_stall_len < 5) out_backpressure_bin = 1;
                else out_backpressure_bin = 2;

                cg_outputs.sample();
                cg_workload.sample();

                // Track repeated output patterns
                if (out_class == last_class) begin
                    repeat_run_len++;
                end else begin
                    if (repeat_run_len > 0) cg_output_patterns.sample();
                    repeat_run_len = 1;
                end
                last_class = out_class;
            end
        end
    endtask

    // =========================================================================
    // External sampling methods (called by sequences/tests for event-driven coverage)
    // These allow tests to push coverage events for categories 2, 4, 5
    // without needing to decode protocol headers in the coverage component.
    // =========================================================================

    // Called by cfg sequence when it sends a config message
    function void sample_cfg_msg(bit is_threshold, int layer_id, int order_slot);
        cfg_msg_type  = is_threshold;
        cfg_layer_id  = layer_id;
        cfg_msg_order = order_slot;
        cg_cfg_content.sample();
    endfunction

    // Called by test when weight density is computed for a layer
    function void sample_weight_density(int density_pct, int layer_id);
        weight_density_pct = density_pct;
        weight_layer_id    = layer_id;
        cg_weight_density.sample();
    endfunction

    // Called by test when threshold magnitude is known for a layer
    function void sample_thresh(int mag, int layer_id);
        thresh_mag      = mag;
        thresh_layer_id = layer_id;
        cg_thresh.sample();
    endfunction

    // Called by test for reconfiguration events (Category 4)
    function void sample_reconfig(int rtype, int num_layers);
        reconfig_type  = rtype;
        layers_touched = num_layers;
        cg_reconfig.sample();
    endfunction

    // Called by test for reset events (Category 5)
    function void sample_reset_event(int phase, int count);
        reset_phase = phase;
        reset_count = count;
        cg_reset.sample();
    endfunction

    // Called by test for post-reset config choice (Category 5)
    function void sample_post_reset(bit same_cfg);
        post_reset_same_cfg = same_cfg;
        cg_reset_post.sample();
    endfunction

    // Called by test for pixel diversity (Category 3/workload)
    function void sample_pixel(int pclass);
        pixel_class = pclass;
    endfunction

endclass
`endif
