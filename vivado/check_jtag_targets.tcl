set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname $script_dir]
set report_dir [file join $repo_root build jtag_check]
file mkdir $report_dir
set report_path [file join $report_dir vivado_jtag_targets.txt]
set report [open $report_path w]

proc log_line {fh msg} {
    puts $msg
    puts $fh $msg
}

log_line $report "Vivado JTAG target check"
log_line $report "Report: $report_path"

open_hw_manager
connect_hw_server -allow_non_jtag

log_line $report "HW_TARGETS_START"
foreach target [get_hw_targets *] {
    log_line $report $target
}
log_line $report "HW_TARGETS_END"

set targets [get_hw_targets *]
if {[llength $targets] > 0} {
    foreach target $targets {
        current_hw_target $target
        catch {open_hw_target} result
        if {$result ne ""} {
            log_line $report "OPEN_TARGET_RESULT $target $result"
        }
    }
}

log_line $report "HW_DEVICES_START"
foreach dev [get_hw_devices *] {
    log_line $report $dev
}
log_line $report "HW_DEVICES_END"

disconnect_hw_server
close $report
