`ifndef _BNN_DRIVER_SVH_
`define _BNN_DRIVER_SVH_

`include "bnn_item.svh"
`include "scoreboard.svh"

class bnn_driver #(
    int CONFIG_BUS_WIDTH  = 64,
    int INPUT_BUS_WIDTH   = 64,
    int INPUT_DATA_WIDTH  = 8,
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
);
    localparam int INPUTS_PER_CYCLE = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;
    localparam int BYTES_PER_INPUT  = INPUT_DATA_WIDTH / 8;

    typedef bit [INPUT_BUS_WIDTH-1:0]   input_bus_word_t;
    typedef bit [INPUT_BUS_WIDTH/8-1:0] input_keep_t;

    virtual bnn_bfm #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) bfm;

    bnn_scoreboard #(
        .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) scoreboard_h;

    real config_valid_probability;
    real data_in_valid_probability;
    bit  debug;

    function new(
        virtual bnn_bfm #(
            .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
            .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
            .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
        ) bfm,
        bnn_scoreboard #(
            .OUTPUT_BUS_WIDTH (OUTPUT_BUS_WIDTH),
            .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
        ) scoreboard_h,
        real config_valid_probability,
        real data_in_valid_probability,
        bit  debug
    );
        this.bfm                       = bfm;
        this.scoreboard_h              = scoreboard_h;
        this.config_valid_probability  = config_valid_probability;
        this.data_in_valid_probability = data_in_valid_probability;
        this.debug                     = debug;
    endfunction

    function automatic bit chance(real p);
        if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    task automatic pack_image_beat(
        input  bit [INPUT_DATA_WIDTH-1:0] pixels[],
        input  int                        start_idx,
        output input_bus_word_t           beat_data,
        output input_keep_t               beat_keep
    );
        beat_data = '0;
        beat_keep = '0;

        for (int k = 0; k < INPUTS_PER_CYCLE; k++) begin
            if (start_idx + k < pixels.size()) begin
                beat_data[k*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH] = pixels[start_idx+k];
                beat_keep[k*BYTES_PER_INPUT+:BYTES_PER_INPUT]   = '1;
            end
        end
    endtask

    task automatic run(bnn_test_context #(CONFIG_BUS_WIDTH, INPUT_DATA_WIDTH) ctx);
        input_bus_word_t beat_data;
        input_keep_t     beat_keep;

        $display("[%0t] Streaming weights and thresholds.", $realtime);
        for (int i = 0; i < ctx.config_bus_data_stream.size(); i++) begin
            while (!chance(config_valid_probability)) begin
                bfm.clear_config();
                @(posedge bfm.clk iff bfm.config_ready);
            end

            bfm.drive_config_beat(
                ctx.config_bus_data_stream[i],
                ctx.config_bus_keep_stream[i],
                i == ctx.config_bus_data_stream.size() - 1
            );
        end
        bfm.clear_config();

        bfm.wait_for_input_ready();
        repeat (5) @(posedge bfm.clk);

        foreach (ctx.images[i]) begin
            int expected_pred;

            expected_pred = ctx.model.compute_reference(ctx.images[i].pixels);
            scoreboard_h.push_expected(expected_pred);

            $display("[%0t] Streaming image %0d.", $realtime, ctx.images[i].image_id);
            if (debug) ctx.model.print_inference_trace();

            for (int j = 0; j < ctx.images[i].pixels.size(); j += INPUTS_PER_CYCLE) begin
                pack_image_beat(ctx.images[i].pixels, j, beat_data, beat_keep);

                while (!chance(data_in_valid_probability)) begin
                    bfm.clear_data_in();
                    @(posedge bfm.clk iff bfm.data_in_ready);
                end

                bfm.drive_data_in_beat(
                    beat_data,
                    beat_keep,
                    (j + INPUTS_PER_CYCLE >= ctx.images[i].pixels.size())
                );

                if (ctx.images[i].image_id == 0 && j == 0) ctx.throughput.start_test();
                if (j == 0) ctx.latency.start_event(ctx.images[i].image_id);
            end

            bfm.clear_data_in();
            @(posedge bfm.clk);
        end

        $display("[%0t] All images loaded, waiting for outputs.", $realtime);
    endtask
endclass

`endif
