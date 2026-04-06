`ifndef _BNN_FCC_ENV_SVH_
`define _BNN_FCC_ENV_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import axi4_stream_pkg::*;
`include "bnn_fcc_coverage.svh"

class bnn_fcc_env extends uvm_env;
    `uvm_component_utils(bnn_fcc_env)

    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH ) in_axi_item_t;
    typedef axi4_stream_seq_item #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_axi_item_t;

    // Agents
    axi4_stream_agent #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_agent;
    axi4_stream_agent #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH ) in_agent;
    axi4_stream_agent #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_agent;

    // Scoreboard
    bnn_fcc_scoreboard scoreboard;

    // Per-stream coverage
    bnn_cfg_coverage    cfg_coverage;
    bnn_input_coverage  input_coverage;
    bnn_output_coverage output_coverage;
    bnn_system_coverage system_coverage;

    // Virtual interfaces
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH) cfg_vif;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH ) in_vif;
    virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH) out_vif;

    // Driver delay knobs
    int cfg_min_driver_delay;
    int cfg_max_driver_delay;
    int in_min_driver_delay;
    int in_max_driver_delay;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg_agent = axi4_stream_agent #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH)::type_id::create("cfg_agent", this);
        in_agent  = axi4_stream_agent #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH )::type_id::create("in_agent",  this);
        out_agent = axi4_stream_agent #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH)::type_id::create("out_agent", this);
        out_agent.is_active = UVM_PASSIVE;

        scoreboard      = bnn_fcc_scoreboard::type_id::create("scoreboard", this);
        cfg_coverage    = bnn_cfg_coverage   ::type_id::create("cfg_coverage", this);
        input_coverage  = bnn_input_coverage ::type_id::create("input_coverage", this);
        output_coverage = bnn_output_coverage::type_id::create("output_coverage", this);
        system_coverage = bnn_system_coverage::type_id::create("system_coverage", this);

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::CONFIG_BUS_WIDTH))::get(this, "", "cfg_vif", cfg_vif))
            `uvm_fatal("NO_CFG_VIF", "cfg_vif not set")

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::INPUT_BUS_WIDTH))::get(this, "", "in_vif", in_vif))
            `uvm_fatal("NO_IN_VIF", "in_vif not set")

        if (!uvm_config_db#(virtual axi4_stream_if #(bnn_fcc_uvm_pkg::OUTPUT_BUS_WIDTH))::get(this, "", "out_vif", out_vif))
            `uvm_fatal("NO_OUT_VIF", "out_vif not set")

        // Separate knobs per input stream
        if (!uvm_config_db#(int)::get(this, "", "cfg_min_driver_delay", cfg_min_driver_delay))
            cfg_min_driver_delay = 1;
        if (!uvm_config_db#(int)::get(this, "", "cfg_max_driver_delay", cfg_max_driver_delay))
            cfg_max_driver_delay = 1;

        if (!uvm_config_db#(int)::get(this, "", "in_min_driver_delay", in_min_driver_delay))
            in_min_driver_delay = 1;
        if (!uvm_config_db#(int)::get(this, "", "in_max_driver_delay", in_max_driver_delay))
            in_max_driver_delay = 1;
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // The scoreboard reconstructs complete images/config packets from the
        // monitored AXI traffic, so its monitors must emit packet-level items.
        cfg_agent.monitor.is_packet_level = 1'b1;
        in_agent.monitor.is_packet_level  = 1'b1;
        out_agent.monitor.is_packet_level = 1'b1;

        // Config stream
        cfg_agent.driver.vif  = cfg_vif;
        cfg_agent.monitor.vif = cfg_vif;

        // Input image stream
        in_agent.driver.vif  = in_vif;
        in_agent.monitor.vif = in_vif;

        // Output stream
        // The output agent is passive, so only the monitor binds to the DUT.
        out_agent.monitor.vif = out_vif;

        // Scoreboard connections
        cfg_agent.monitor.ap.connect(scoreboard.cfg_ae);
        in_agent.monitor.ap.connect(scoreboard.in_ae);
        out_agent.monitor.ap.connect(scoreboard.out_ae);

        // Coverage connections
        cfg_agent.monitor.ap.connect(cfg_coverage.cfg_ae);
        in_agent.monitor.ap.connect(input_coverage.in_ae);
        out_agent.monitor.ap.connect(output_coverage.out_ae);
        in_agent.monitor.ap.connect(system_coverage.in_ae);

        // Driver delay configuration
        cfg_agent.driver.set_delay(cfg_min_driver_delay, cfg_max_driver_delay);
        in_agent.driver.set_delay(in_min_driver_delay, in_max_driver_delay);
    endfunction

endclass

`endif
