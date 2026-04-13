// Pawin Ruangkanit
// University of Florida
//
// Starts on class 0, then holds a long repeated run before changing class.

`ifndef _BNN_FCC_OUTPUT_CLASS0_LONG_RUN_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS0_LONG_RUN_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class0_long_run_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class0_long_run_test)

    function new(string name = "bnn_fcc_output_class0_long_run_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-0 first/repeat/long-run coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();

        for (int i = 0; i < 12; i++)
            image_indices.push_back(3);

        image_indices.push_back(2);
    endfunction
endclass

`endif
