// Greg Stitt
// University of Florida

`ifndef _NP_ITEM_SVH_
`define _NP_ITEM_SVH_

// The transaction 'item' for this class is the data inputs, x and w and the threshold
class np_item #(
    P_WIDTH,
    ACC_WIDTH
);
  // inputs
  rand bit [P_WIDTH-1:0] x, w;
  rand bit valid_in;
  rand bit [ACC_WIDTH-1:0] threshold;
  bit last;

  // Output
  bit y, y_valid;

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
