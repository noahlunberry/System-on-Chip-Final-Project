// Lightweight BFM for the bnn_fcc OOP testbench.
//
// This interface intentionally mirrors the DUT ports directly so the class-based
// environment can preserve the behavior of verification/bnn_fcc_tb.sv without
// hiding the protocol details behind a larger framework.

`ifndef _BNN_BFM_SV_
`define _BNN_BFM_SV_

interface bnn_bfm #(
    parameter int CONFIG_BUS_WIDTH = 64,
    parameter int INPUT_BUS_WIDTH  = 64,
    parameter int OUTPUT_BUS_WIDTH = 8
) (
    input logic clk
);
    logic rst;

    logic                          config_valid;
    logic                          config_ready;
    logic [CONFIG_BUS_WIDTH-1:0]   config_data;
    logic [CONFIG_BUS_WIDTH/8-1:0] config_keep;
    logic                          config_last;

    logic                         data_in_valid;
    logic                         data_in_ready;
    logic [INPUT_BUS_WIDTH-1:0]   data_in_data;
    logic [INPUT_BUS_WIDTH/8-1:0] data_in_keep;
    logic                         data_in_last;

    logic                          data_out_valid;
    logic                          data_out_ready;
    logic [OUTPUT_BUS_WIDTH-1:0]   data_out_data;
    logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep;
    logic                          data_out_last;

    initial begin
        if (CONFIG_BUS_WIDTH % 8 != 0) $fatal(1, "CONFIG_BUS_WIDTH must be byte aligned.");
        if (INPUT_BUS_WIDTH % 8 != 0) $fatal(1, "INPUT_BUS_WIDTH must be byte aligned.");
        if (OUTPUT_BUS_WIDTH % 8 != 0) $fatal(1, "OUTPUT_BUS_WIDTH must be byte aligned.");
    end

    // Match the AXI assertions present in axi4_stream_if.sv for the two driven inputs.
    assert property (@(posedge clk) disable iff (rst) $fell(config_valid) |-> $past(config_ready, 1))
    else $error("config_valid must remain asserted until config_ready is high.");

    assert property (@(posedge clk) disable iff (rst) $fell(data_in_valid) |-> $past(data_in_ready, 1))
    else $error("data_in_valid must remain asserted until data_in_ready is high.");

    task automatic clear_config();
        config_valid <= 1'b0;
        config_data  <= '0;
        config_keep  <= '0;
        config_last  <= 1'b0;
    endtask

    task automatic clear_data_in();
        data_in_valid <= 1'b0;
        data_in_data  <= '0;
        data_in_keep  <= '0;
        data_in_last  <= 1'b0;
    endtask

    task automatic reset(int cycles);
        rst <= 1'b1;
        clear_config();
        clear_data_in();
        data_out_ready <= 1'b1;

        repeat (cycles) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (cycles) @(posedge clk);
    endtask

    task automatic drive_config_beat(
        input logic [CONFIG_BUS_WIDTH-1:0]   data,
        input logic [CONFIG_BUS_WIDTH/8-1:0] keep,
        input logic                          last
    );
        config_valid <= 1'b1;
        config_data  <= data;
        config_keep  <= keep;
        config_last  <= last;
        @(posedge clk iff config_ready);
    endtask

    task automatic drive_data_in_beat(
        input logic [INPUT_BUS_WIDTH-1:0]   data,
        input logic [INPUT_BUS_WIDTH/8-1:0] keep,
        input logic                         last
    );
        data_in_valid <= 1'b1;
        data_in_data  <= data;
        data_in_keep  <= keep;
        data_in_last  <= last;
        @(posedge clk iff data_in_ready);
    endtask

    task automatic wait_for_input_ready();
        wait (data_in_ready);
    endtask

endinterface

`endif
