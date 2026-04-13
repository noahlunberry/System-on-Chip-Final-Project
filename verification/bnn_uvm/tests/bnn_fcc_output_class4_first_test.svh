// Pawin Ruangkanit
// University of Florida
//
// Starts on class 4, then later repeats class 3 so one short directed test
// contributes to both missing output-class bins.

`ifndef _BNN_FCC_OUTPUT_CLASS4_FIRST_TEST_SVH_
`define _BNN_FCC_OUTPUT_CLASS4_FIRST_TEST_SVH_

`include "uvm_macros.svh"
import uvm_pkg::*;
import bnn_fcc_tb_pkg::*;

class bnn_fcc_output_class4_first_test extends bnn_fcc_output_directed_base_test;
    `uvm_component_utils(bnn_fcc_output_class4_first_test)

    function new(string name = "bnn_fcc_output_class4_first_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function string get_scenario_name();
        return "class-4 first and class-3 repeat coverage";
    endfunction

    protected virtual function void build_image_indices(ref int image_indices[$]);
        image_indices.delete();
        image_indices.push_back(4);
        image_indices.push_back(18);
        image_indices.push_back(30);
        image_indices.push_back(0);
    endfunction
endclass

`endif
