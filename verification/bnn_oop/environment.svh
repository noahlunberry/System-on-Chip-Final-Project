`ifndef _BNN_ENVIRONMENT_SVH_
`define _BNN_ENVIRONMENT_SVH_

`include "driver.svh"
`include "monitor.svh"
`include "ready_driver.svh"
`include "scoreboard.svh"

class bnn_environment #(
    int CONFIG_BUS_WIDTH  = 64,
    int INPUT_BUS_WIDTH   = 64,
    int INPUT_DATA_WIDTH  = 8,
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
);
    bnn_driver #(
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .INPUT_DATA_WIDTH (INPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) driver_h;

    bnn_output_monitor #(
        .CONFIG_BUS_WIDTH (CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH  (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) monitor_h;

    bnn_ready_driver #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) ready_driver_h;

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
        real config_valid_probability,
        real data_in_valid_probability,
        bit  toggle_data_out_ready,
        bit  debug
    );
        scoreboard_h   = new();
        driver_h       = new(bfm, scoreboard_h, config_valid_probability, data_in_valid_probability, debug);
        monitor_h      = new(bfm, scoreboard_h);
        ready_driver_h = new(bfm, toggle_data_out_ready);
    endfunction

    task run(bnn_test_context #(CONFIG_BUS_WIDTH, INPUT_DATA_WIDTH) ctx);
        scoreboard_h.set_target_count(ctx.num_tests);

        fork : background
            ready_driver_h.run();
            monitor_h.run(ctx.num_tests, ctx.latency, ctx.throughput);
        join_none

        driver_h.run(ctx);
        scoreboard_h.wait_for_done();
        disable background;
    endtask

    function int get_passed();
        return scoreboard_h.get_passed();
    endfunction

    function int get_failed();
        return scoreboard_h.get_failed();
    endfunction

    function void report_status();
        scoreboard_h.report_status();
    endfunction
endclass

`endif
