interface bnn_fcc_ctrl_if (
    input logic clk
);
    // A tiny control interface used only for TB/UVM coordination. The AXI
    // agents still bind directly to their own stream interfaces; this wrapper
    // simply gives tests and coverage a shared reset handle.
    logic rst;
    logic out_ready_force_en;
    logic out_ready_force_val;

    task automatic pulse_reset(int cycles = 5);
        // Centralize reset pulsing here so every mid-test reset uses the same
        // timing convention as the power-on reset sequence in the top TB.
        rst <= 1'b1;
        repeat (cycles) @(posedge clk);
        rst <= 1'b0;
    endtask

    task automatic force_output_ready(bit value);
        out_ready_force_val = value;
        out_ready_force_en = 1'b1;
    endtask

    task automatic release_output_ready();
        out_ready_force_en = 1'b0;
    endtask
endinterface
