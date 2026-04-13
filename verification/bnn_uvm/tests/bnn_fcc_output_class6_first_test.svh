// Pawin Ruangkanit
// University of Florida
//
// Starts on class 6, then later repeats class 7 so the run fills two missing
// output-transition bins without needing separate boilerplate tests.

`ifndef _BNN_FCC_OUTPUT_CLASS6_FIRST_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS6_FIRST_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class6_first_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class6_first_test)

    function new(string name = "bnn_fcc_output_class6_first_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-6 first and class-7 repeat coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        image_indices.push_back(8);
        image_indices.push_back(0);
        image_indices.push_back(17);
        image_indices.push_back(3);
    endfunction
endclass

`endif
