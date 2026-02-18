// Greg Stitt
// University of Florida

`ifndef _NP_ITEM_SVH_
`define _NP_ITEM_SVH_

// The transaction 'item' for this class is the data inputs, x and w
class np_item #(
    TOTAL_INPUTS,
    ACC_WIDTH
);
  rand bit [TOTAL_INPUTS-1:0] x, w;
  rand bit valid_in;
  rand bit [ACC_WIDTH-1:0] threshold;

  // Output
  rand bit [ACC_WIDTH-1:0] y;

  // A uniform distribution of go values probably isn't what we want, so
  // we'll make sure go is 1'b1 90% of the time.
  constraint c_valid_in_dist {
    valid_in dist {
      1 :/ 90,
      0 :/ 10
    };
  }
endclass

`endif
