`ifndef _BNN_MONITOR_SVH_
`define _BNN_MONITOR_SVH_

`include "scoreboard.svh"

class bnn_output_monitor #(
    int CONFIG_BUS_WIDTH  = 64,
    int INPUT_BUS_WIDTH   = 64,
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
);
    virtual bnn_bfm #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) bfm;

    bnn_scoreboard #(
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) scoreboard_h;

    function new(
        virtual bnn_bfm #(
            .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
            .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
            .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
        ) bfm,
        bnn_scoreboard #(
            .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
            .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
        ) scoreboard_h
    );
        this.bfm          = bfm;
        this.scoreboard_h = scoreboard_h;
    endfunction

    task run(
        input int                               num_tests,
        input bnn_fcc_tb_pkg::LatencyTracker    latency,
        input bnn_fcc_tb_pkg::ThroughputTracker throughput
    );
        int output_count;

        output_count = 0;
        while (output_count < num_tests) begin
            @(posedge bfm.clk iff bfm.data_out_valid && bfm.data_out_ready);

            scoreboard_h.check_output(bfm.data_out_data, output_count);
            latency.end_event(output_count);

            if (output_count == num_tests - 1) throughput.sample_end();

            // Future expansion: check data_out_keep and data_out_last here once
            // you begin targeting protocol-specific output coverage.
            output_count++;
        end
    endtask
endclass

`endif
