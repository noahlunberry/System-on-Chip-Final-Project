`ifndef _BNN_READY_DRIVER_SVH_
`define _BNN_READY_DRIVER_SVH_

class bnn_ready_driver #(
    int CONFIG_BUS_WIDTH = 64,
    int INPUT_BUS_WIDTH  = 64,
    int OUTPUT_BUS_WIDTH = 8
);
    virtual bnn_bfm #(
        .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
        .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
        .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
    ) bfm;

    bit toggle_data_out_ready;

    function new(
        virtual bnn_bfm #(
            .CONFIG_BUS_WIDTH(CONFIG_BUS_WIDTH),
            .INPUT_BUS_WIDTH (INPUT_BUS_WIDTH),
            .OUTPUT_BUS_WIDTH(OUTPUT_BUS_WIDTH)
        ) bfm,
        bit toggle_data_out_ready
    );
        this.bfm                   = bfm;
        this.toggle_data_out_ready = toggle_data_out_ready;
    endfunction

    task run();
        bfm.data_out_ready <= 1'b1;
        @(posedge bfm.clk iff !bfm.rst);

        if (toggle_data_out_ready) begin
            // Future expansion: replace this with directed burst/intermittent
            // ready policies so each scenario can cover a specific backpressure
            // pattern instead of a pure per-cycle random toggle.
            forever begin
                bfm.data_out_ready <= $urandom();
                @(posedge bfm.clk);
            end
        end else begin
            bfm.data_out_ready <= 1'b1;
        end
    endtask
endclass

`endif
