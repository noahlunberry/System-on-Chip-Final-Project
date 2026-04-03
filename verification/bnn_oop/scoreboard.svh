`ifndef _BNN_SCOREBOARD_SVH_
`define _BNN_SCOREBOARD_SVH_

class bnn_scoreboard #(
    int OUTPUT_BUS_WIDTH  = 8,
    int OUTPUT_DATA_WIDTH = 4
);
    typedef bit [OUTPUT_DATA_WIDTH-1:0] expected_t;
    typedef bit [OUTPUT_BUS_WIDTH-1:0]  actual_t;

    expected_t expected_outputs[$];
    int        passed;
    int        failed;
    int        observed_count;
    int        target_count;

    function new();
        passed         = 0;
        failed         = 0;
        observed_count = 0;
        target_count   = 0;
    endfunction

    function void set_target_count(int count);
        target_count = count;
    endfunction

    function void push_expected(int expected_pred);
        expected_outputs.push_back(expected_t'(expected_pred));
    endfunction

    function void check_output(actual_t actual, int output_count);
        if (expected_outputs.size() == 0) begin
            $fatal(1, "No expected output for actual output");
        end

        if (actual == expected_outputs[0]) begin
            passed++;
        end else begin
            $error("Output incorrect for image %0d: actual = %0d vs expected = %0d",
                   output_count, actual, expected_outputs[0]);
            failed++;
        end

        void'(expected_outputs.pop_front());
        observed_count++;
    endfunction

    task wait_for_done();
        wait (observed_count == target_count);
    endtask

    function int get_passed();
        return passed;
    endfunction

    function int get_failed();
        return failed;
    endfunction

    function void report_status();
        $display("Test status: %0d passed, %0d failed", passed, failed);
    endfunction
endclass

`endif
