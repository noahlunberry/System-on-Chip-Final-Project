// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// ENVIRONMENT TOP: bnn_fcc_env
// Maps to: IMPLEMENTATION_PLAN.md §"Target UVM component set"
//
// DESCRIPTION:
// Assembles agents, scoreboard, and coverage collector. Follows the filter_env.svh
// pattern for VIF wiring: read VIFs from config_db, then assign to driver.vif and
// monitor.vif in connect_phase.
//
// Three AXI4-Stream agents:
//   cfg_agent (active master)  - configuration weights/thresholds
//   in_agent  (active master)  - image/activation input
//   out_agent (passive monitor) - DUT output observation
//
// DEVIATION from prior code: Previously did not wire VIFs in env. Now follows
// filter_env.svh exactly: env reads VIFs, assigns to agent sub-components.

`ifndef _BNN_FCC_ENV_SVH_
`define _BNN_FCC_ENV_SVH_

class bnn_fcc_env extends uvm_env;
    `uvm_component_utils(bnn_fcc_env)

    axi4_stream_agent #(64) cfg_agent;
    axi4_stream_agent #(64) in_agent;
    axi4_stream_agent #(8)  out_agent;

    bnn_fcc_scoreboard scoreboard;
    bnn_fcc_coverage   coverage;

    // VIF handles read from config_db (filter_env pattern)
    virtual axi4_stream_if #(64) cfg_vif;
    virtual axi4_stream_if #(64) in_vif;
    virtual axi4_stream_if #(8)  out_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Output agent runs passive — only monitor, no driver
        uvm_config_db#(uvm_active_passive_enum)::set(this, "out_agent", "is_active", UVM_PASSIVE);

        cfg_agent  = axi4_stream_agent #(64)::type_id::create("cfg_agent", this);
        in_agent   = axi4_stream_agent #(64)::type_id::create("in_agent", this);
        out_agent  = axi4_stream_agent #(8)::type_id::create("out_agent", this);

        scoreboard = bnn_fcc_scoreboard::type_id::create("scoreboard", this);
        coverage   = bnn_fcc_coverage::type_id::create("coverage", this);

        // Read VIFs — following filter_env pattern
        if (!uvm_config_db#(virtual axi4_stream_if #(64))::get(this, "", "cfg_vif", cfg_vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for cfg: ", get_full_name()})
        if (!uvm_config_db#(virtual axi4_stream_if #(64))::get(this, "", "in_vif", in_vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for in: ", get_full_name()})
        if (!uvm_config_db#(virtual axi4_stream_if #(8))::get(this, "", "out_vif", out_vif))
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for out: ", get_full_name()})
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Wire VIFs to agent sub-components (filter_env pattern)
        cfg_agent.driver.vif  = cfg_vif;
        cfg_agent.monitor.vif = cfg_vif;
        in_agent.driver.vif   = in_vif;
        in_agent.monitor.vif  = in_vif;
        out_agent.monitor.vif = out_vif;

        // Wire coverage VIFs for cycle-level sampling
        coverage.cfg_vif = cfg_vif;
        coverage.in_vif  = in_vif;
        coverage.out_vif = out_vif;

        // Scoreboard analysis exports (filter_scoreboard pattern)
        cfg_agent.monitor.ap.connect(scoreboard.cfg_ae);
        in_agent.monitor.ap.connect(scoreboard.in_ae);
        out_agent.monitor.ap.connect(scoreboard.out_ae);

        // Coverage analysis exports
        cfg_agent.monitor.ap.connect(coverage.cfg_ae);
        in_agent.monitor.ap.connect(coverage.in_ae);
        out_agent.monitor.ap.connect(coverage.out_ae);
    endfunction
endclass
`endif
