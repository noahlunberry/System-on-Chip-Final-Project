interface bnn_fcc_ctrl_if (
    input logic clk
);
    logic rst;

    task automatic pulse_reset(int cycles = 5);
        rst <= 1'b1;
        repeat (cycles) @(posedge clk);
        rst <= 1'b0;
    endtask
endinterface
