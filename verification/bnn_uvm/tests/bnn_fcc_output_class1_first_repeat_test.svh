// Greg Stitt
// University of Florida
//
// Starts on class 1 and repeats it once before changing to a different class.

`ifndef _BNN_FCC_OUTPUT_CLASS1_FIRST_REPEAT_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS1_FIRST_REPEAT_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class1_first_repeat_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class1_first_repeat_test)

    function new(string name = "bnn_fcc_output_class1_first_repeat_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-1 first/repeat coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        image_indices.push_back(2);
        image_indices.push_back(2);
        image_indices.push_back(3);
    endfunction
endclass

`endif
