// Greg Stitt
// University of Florida
//
// Starts on class 9 and repeats it once before changing class.

`ifndef _BNN_FCC_OUTPUT_CLASS9_FIRST_REPEAT_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS9_FIRST_REPEAT_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class9_first_repeat_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class9_first_repeat_test)

    function new(string name = "bnn_fcc_output_class9_first_repeat_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-9 first/repeat coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        image_indices.push_back(7);
        image_indices.push_back(7);
        image_indices.push_back(3);
    endfunction
endclass

`endif
