# -----------------------------------------------------------------------------
# Install the Avnet/Tria ZUBoard-1CG board definition into Vivado's XHub board
# store for the current Vivado version.
#
# Usage:
#   vivado -mode batch -source vivado/install_zuboard_board_files.tcl
# -----------------------------------------------------------------------------

set store [xhub::get_xstores xilinx_board_store]

puts "INFO: Refreshing Vivado XHub board-store catalog."
xhub::refresh_catalog $store

set items [xhub::get_xitems *ZUBoard_1CG*]
if {[llength $items] == 0} {
  set items [xhub::get_xitems *zuboard*]
}
if {[llength $items] == 0} {
  error "Could not find ZUBoard_1CG in the Vivado XHub board store."
}

puts "INFO: Installing board-store item(s): $items"
xhub::install $items

set local_root [get_property LOCAL_ROOT_DIR $store]
set_param board.repoPaths [list $local_root]

puts "INFO: Vivado board repository path: $local_root"
puts "INFO: Matching board parts after install:"
puts [get_board_parts -quiet *zub*]
