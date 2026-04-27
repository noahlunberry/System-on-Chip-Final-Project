# -----------------------------------------------------------------------------
# Create a Vivado project for the ZUBoard-1CG bare-metal BNN FCC accelerator.
#
# Usage:
#   vivado -mode batch -source vivado/create_zuboard_bnn_project.tcl
#   vivado -mode batch -source vivado/create_zuboard_bnn_project.tcl -tclargs -build_bitstream
#
# The script uses a small accelerator configuration:
#   PARALLEL_INPUTS  = 8
#   PARALLEL_NEURONS = '{8, 8, 10}
#
# The BNN AXI4-Lite slave is mapped at 0xA000_0000 with a 64 KiB aperture.
# -----------------------------------------------------------------------------

set script_dir [file dirname [info script]]
if {[file pathtype $script_dir] ne "absolute"} {
  set script_dir [file join [pwd] $script_dir]
}
set repo_root [file dirname $script_dir]

set project_name "zuboard_bnn_fcc"
set bd_name      "zuboard_bnn_fcc_bd"
set project_dir  [file join $repo_root "build" "vivado" $project_name]
set part_name    "xczu1cg-sbva484-1-e"
set accel_base   0xA0000000
set accel_range  0x00010000
set pl_clk_mhz   100
set build_bitstream 0
set jobs 4

for {set i 0} {$i < [llength $argv]} {incr i} {
  set arg [lindex $argv $i]
  switch -- $arg {
    "-build_bitstream" {
      set build_bitstream 1
    }
    "-jobs" {
      incr i
      if {$i >= [llength $argv]} {
        error "-jobs requires a value"
      }
      set jobs [lindex $argv $i]
    }
    default {
      error "Unknown argument: $arg"
    }
  }
}

proc add_sv_sources {repo_root} {
  set rtl_files [list \
    "rtl/delay.sv" \
    "rtl/fifo_vr.sv" \
    "rtl/replay_buffer.sv" \
    "rtl/ram_sdp.sv" \
    "rtl/xnor_add_tree.sv" \
    "rtl/add_tree.sv" \
    "rtl/argmax_tree.sv" \
    "rtl/neuron_processor.sv" \
    "rtl/neuron_controller.sv" \
    "rtl/config_controller.sv" \
    "rtl/tkeep_byte_compactor.sv" \
    "rtl/vw_buffer.sv" \
    "rtl/config_manager_parser.sv" \
    "rtl/config_manager_pad_fsm.sv" \
    "rtl/config_manager.sv" \
    "rtl/bnn_layer.sv" \
    "rtl/bnn.sv" \
    "rtl/data_in_manager.sv" \
    "rtl/bnn_fcc.sv" \
    "rtl/bnn_fcc_axi_lite.sv" \
    "vivado/hdl/bnn_fcc_vivado_axi_lite_small.v" \
  ]

  set normalized_files [list]
  foreach rel_file $rtl_files {
    set abs_file [file join $repo_root $rel_file]
    if {![file exists $abs_file]} {
      error "Missing RTL source: $abs_file"
    }
    lappend normalized_files $abs_file
  }

  add_files -norecurse -fileset sources_1 $normalized_files
  set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] "*.sv"]
  set_property file_type Verilog [get_files -of_objects [get_filesets sources_1] "*.v"]
  update_compile_order -fileset sources_1
}

proc set_cell_property_if_present {cell prop value} {
  if {[lsearch -exact [list_property $cell] $prop] >= 0} {
    set_property $prop $value $cell
  }
}

proc set_xhub_board_repo_path {} {
  set status [catch {
    set store [xhub::get_xstores xilinx_board_store]
    set local_root [get_property LOCAL_ROOT_DIR $store]
    if {$local_root ne ""} {
      set_param board.repoPaths [list $local_root]
      puts "INFO: Using Vivado board repo path: $local_root"
    }
  } result]
  if {$status != 0} {
    puts "WARNING: Could not set XHub board repo path automatically: $result"
  }
}

proc set_first_matching_zuboard_part {} {
  set matches [get_board_parts -quiet *zuboard_1cg*]
  if {[llength $matches] == 0} {
    set matches [get_board_parts -quiet *zub*]
  }
  set selected ""

  foreach board_part $matches {
    if {[string match -nocase "*1cg*" $board_part]} {
      set selected $board_part
      break
    }
  }

  if {$selected ne ""} {
    puts "INFO: Using Vivado board part: $selected"
    set_property board_part $selected [current_project]
  } else {
    puts "WARNING: No ZUBoard-1CG Vivado board part was found."
    puts "WARNING: Install the Avnet/Tria ZUBoard board files for correct PS DDR/MIO presets."
    puts "WARNING: Continuing with the device part only: [get_property PART [current_project]]"
  }
}

proc apply_ps_preset_if_available {ps_cell} {
  set board_part [get_property board_part [current_project]]
  if {$board_part eq ""} {
    return
  }

  set status [catch {
    apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
      -config {apply_board_preset "1"} \
      $ps_cell
  } result]

  if {$status != 0} {
    puts "WARNING: Board automation did not apply cleanly: $result"
    puts "WARNING: The project was created, but PS DDR/MIO settings may need manual review."
  }
}

proc connect_existing_pins {net_obj pin_candidates} {
  set connected [list]
  foreach pin $pin_candidates {
    set pin_obj [get_bd_pins -quiet $pin]
    if {[llength $pin_obj] > 0} {
      connect_bd_net $net_obj $pin_obj
      lappend connected $pin_obj
    }
  }
  return $connected
}

proc disable_run_reports {run_name} {
  set run_obj [get_runs -quiet $run_name]
  if {[llength $run_obj] == 0} {
    return
  }

  set_property set_report_strategy_name 1 $run_obj
  set_property report_strategy {No Reports} $run_obj
  set_property set_report_strategy_name 0 $run_obj
}

set_xhub_board_repo_path

file mkdir $project_dir
create_project -force $project_name $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set_first_matching_zuboard_part
add_sv_sources $repo_root

create_bd_design $bd_name

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
apply_ps_preset_if_available $ps

# Keep these assignments guarded because property names can vary across Vivado
# versions. They are the standard knobs needed for PL clock and PS AXI master.
set_cell_property_if_present $ps CONFIG.PSU__FPGA_PL0_ENABLE 1
set_cell_property_if_present $ps CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $pl_clk_mhz
set_cell_property_if_present $ps CONFIG.PSU__USE__M_AXI_GP0 1
set_cell_property_if_present $ps CONFIG.PSU__USE__M_AXI_GP1 0
set_cell_property_if_present $ps CONFIG.PSU__USE__M_AXI_GP2 0

set accel [create_bd_cell -type module -reference bnn_fcc_vivado_axi_lite_small bnn_accel_0]
set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_smc_0]
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] $smc
set rst_sync [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_pl_0]
set rst_inv [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:* ps_resetn_inv]
set_property -dict [list CONFIG.C_OPERATION not CONFIG.C_SIZE 1] $rst_inv
set rst_const_high [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* rst_const_high]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] $rst_const_high
set rst_const_low [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* rst_const_low]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] $rst_const_low

set ps_axi [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/M_AXI_HPM0_FPD]
if {[llength $ps_axi] == 0} {
  error "PS M_AXI_HPM0_FPD is not enabled. Check the Zynq UltraScale+ PS configuration."
}

set accel_axi [get_bd_intf_pins -quiet bnn_accel_0/S_AXI]
if {[llength $accel_axi] == 0} {
  error "Vivado did not infer the BNN S_AXI interface. Check X_INTERFACE attributes."
}

connect_bd_intf_net $ps_axi [get_bd_intf_pins axi_smc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M00_AXI] $accel_axi

set pl_clk [get_bd_pins -quiet zynq_ultra_ps_e_0/pl_clk0]
if {[llength $pl_clk] == 0} {
  error "PS pl_clk0 is not enabled. Check the Zynq UltraScale+ PS configuration."
}

connect_bd_net $pl_clk [get_bd_pins bnn_accel_0/s_axi_aclk]
connect_bd_net $pl_clk [get_bd_pins axi_smc_0/aclk]
connect_bd_net $pl_clk [get_bd_pins rst_pl_0/slowest_sync_clk]
connect_existing_pins $pl_clk [list \
  "zynq_ultra_ps_e_0/maxihpm0_fpd_aclk" \
  "zynq_ultra_ps_e_0/maxihpm0_lpd_aclk" \
]

set pl_resetn [get_bd_pins -quiet zynq_ultra_ps_e_0/pl_resetn0]
if {[llength $pl_resetn] == 0} {
  error "PS pl_resetn0 is not enabled. Check the Zynq UltraScale+ PS configuration."
}

connect_bd_net $pl_resetn [get_bd_pins ps_resetn_inv/Op1]
connect_bd_net [get_bd_pins ps_resetn_inv/Res] [get_bd_pins rst_pl_0/ext_reset_in]
connect_bd_net [get_bd_pins rst_const_high/dout] [get_bd_pins rst_pl_0/dcm_locked]
connect_bd_net [get_bd_pins rst_const_high/dout] [get_bd_pins rst_pl_0/aux_reset_in]
connect_bd_net [get_bd_pins rst_const_low/dout] [get_bd_pins rst_pl_0/mb_debug_sys_rst]
connect_bd_net [get_bd_pins rst_pl_0/peripheral_aresetn] [get_bd_pins bnn_accel_0/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_pl_0/peripheral_aresetn] [get_bd_pins axi_smc_0/aresetn]

assign_bd_address \
  -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
  -offset $accel_base \
  -range $accel_range \
  [get_bd_addr_segs -of_objects $accel_axi]

validate_bd_design
save_bd_design

set bd_file [get_files -quiet ${bd_name}.bd]
set wrapper_file [make_wrapper -files $bd_file -top]
add_files -norecurse -fileset sources_1 $wrapper_file
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "INFO: Created Vivado project: [file join $project_dir ${project_name}.xpr]"
puts [format "INFO: BNN AXI4-Lite base address: 0x%08X" $accel_base]

if {$build_bitstream} {
  # Vivado's default implementation report strategy can spend a long time in
  # report_power. Build the bitstream first, then emit focused signoff reports.
  disable_run_reports impl_1

  launch_runs synth_1 -jobs $jobs
  wait_on_run synth_1
  if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis did not complete"
  }

  launch_runs impl_1 -to_step write_bitstream -jobs $jobs
  wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation/bitstream did not complete"
  }

  open_run impl_1
  set report_dir [file join $project_dir "reports"]
  file mkdir $report_dir
  report_drc -file [file join $report_dir "${project_name}_drc_routed.rpt"]
  report_route_status -file [file join $report_dir "${project_name}_route_status.rpt"]
  report_timing_summary -max_paths 10 -report_unconstrained -warn_on_violation \
    -file [file join $report_dir "${project_name}_timing_summary_routed.rpt"]

  set xsa_file [file join $project_dir "${project_name}.xsa"]
  write_hw_platform -fixed -include_bit -force $xsa_file
  puts "INFO: Exported hardware platform: $xsa_file"
}
