open_hw_manager
connect_hw_server -allow_non_jtag

set targets [get_hw_targets *]
puts "HW_TARGETS_START"
foreach target $targets {
    puts $target
}
puts "HW_TARGETS_END"

if {[llength $targets] > 0} {
    current_hw_target [lindex $targets 0]
    open_hw_target
}

puts "HW_DEVICES_START"
foreach dev [get_hw_devices *] {
    puts $dev
}
puts "HW_DEVICES_END"

set zynq_devices [get_hw_devices -quiet xczu*]
if {[llength $zynq_devices] > 0} {
    current_hw_device [lindex $zynq_devices 0]
}
