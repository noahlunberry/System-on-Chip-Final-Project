set output_dir ./outputs

if {![file exists "$output_dir/post_place.dcp"]} {
    error "Missing checkpoint: $output_dir/post_place.dcp"
}

puts "----------------------------------------"
puts " Resume Route From post_place.dcp"
puts "----------------------------------------"

open_checkpoint $output_dir/post_place.dcp

# Skip Physical Synthesis In Router. This is the stage currently crashing in
# the default OpenFlex flow, but a plain routed checkpoint is still legal and
# sufficient to generate the normal post-route reports.
route_design -no_psir -timing_summary

write_checkpoint -force $output_dir/post_route.dcp
report_route_status -file $output_dir/post_route_status.rpt
report_timing_summary -file $output_dir/post_route_timing_summary.rpt
report_power -file $output_dir/post_route_power.rpt
report_drc -file $output_dir/post_imp_drc.rpt
report_design_analysis -timing -logic_level_distribution \
    -of_timing_paths [get_timing_paths -max_paths 10000 -slack_lesser_than 0] \
    -file $output_dir/route_vios.rpt
report_timing -of [get_timing_paths -max_paths 1000 -slack_lesser_than 0] \
    -file $output_dir/route_paths.rpt \
    -rpx $output_dir/route_paths.rpx

set wns ""
foreach timing_entry [get_timing_paths -delay_type max] {
    set slack [lindex [get_property SLACK $timing_entry] 0]
    if {$wns eq "" || $slack < $wns} {
        set wns $slack
    }
}

if {$wns ne ""} {
    set clock_period [get_property PERIOD [get_clocks clk]]
    set fMax [expr (1000 / ($clock_period - $wns))]
} else {
    set fMax "n/a"
}

set utilization_output [get_utilization]
set vivado_report_file "vivado_report.txt"
set file_id [open $vivado_report_file "w"]
puts $file_id $fMax
puts $file_id $utilization_output
close $file_id

puts "----------------------------------------"
puts " Resume Route Complete"
puts "----------------------------------------"
