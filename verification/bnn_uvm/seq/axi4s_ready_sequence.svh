// Greg Stitt (Architecture Outline) / BNN FCC UVM Testbench
//
// SEQUENCE: axi4s_ready_sequence
// Maps to: IMPLEMENTATION_PLAN.md - "Sink-side backpressure sequences"
//
// DESCRIPTION:
// Backpressure generator simulating realistic downstream congestion. 
// Specifically structured to run in parallel directly talking to the VIF rather
// than blocking the standard sequencer since it operates entirely on the `tready` line.
// We configure random wait epochs conforming to constraints to fulfill backpressure coverage.

`ifndef _AXI4S_READY_SEQUENCE_SVH_
`define _AXI4S_READY_SEQUENCE_SVH_

class axi4s_ready_sequence extends uvm_sequence;
    `uvm_object_utils(axi4s_ready_sequence)

    rand int unsigned ready_on_min, ready_on_max;
    rand int unsigned ready_off_min, ready_off_max;

    constraint ready_on_c {
        ready_on_min <= ready_on_max;
        ready_on_max <= 20;
    }

    constraint ready_off_c {
        ready_off_min <= ready_off_max;
        ready_off_max <= 20;
    }

    function new(string name="axi4s_ready_sequence");
        super.new(name);
        ready_on_min = 1;
        ready_on_max = 5;
        ready_off_min = 0;
        ready_off_max = 2;
    endfunction

    virtual task body();
        virtual axi4_stream_if #(8) vif;
        if (!uvm_config_db#(virtual axi4_stream_if #(8))::get(null, "*", "out_vif", vif)) begin
            `uvm_fatal("NO_VIF", "Could not get out_vif for ready sequence")
        end

        forever begin
            int unsigned on_cycles, off_cycles;
            if (!std::randomize(on_cycles, off_cycles) with {
                on_cycles inside {[ready_on_min:ready_on_max]};
                off_cycles inside {[ready_off_min:ready_off_max]};
            }) begin
                `uvm_fatal("RAND_FAIL", "Failed to randomize ready sequence")
            end

            vif.tready <= 1'b1;
            repeat (on_cycles) @(posedge vif.aclk);

            if (off_cycles > 0) begin
                vif.tready <= 1'b0;
                repeat (off_cycles) @(posedge vif.aclk);
            end
        end
    endtask
endclass
`endif
