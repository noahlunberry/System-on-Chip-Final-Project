interface bnn_fcc_ctrl_if (
    input logic clk
);
    // A tiny control interface used only for TB/UVM coordination. The AXI
    // agents still bind directly to their own stream interfaces; this wrapper
    // simply gives tests and coverage a shared reset handle.
    logic rst;

    task automatic pulse_reset(int cycles = 5);
        // Centralize reset pulsing here so every mid-test reset uses the same
        // timing convention as the power-on reset sequence in the top TB.
        rst <= 1'b1;
        repeat (cycles) @(posedge clk);
        rst <= 1'b0;
    endtask
endinterface
