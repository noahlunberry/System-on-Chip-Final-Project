# Try to clear a stale ZynqMP DAP transaction error without manually cycling power.

connect -url TCP:127.0.0.1:3121
after 1000

puts "BEFORE_TARGETS_START"
targets
puts "BEFORE_TARGETS_END"

set selected 0
foreach filter {
    {name =~ "*PMU*"}
    {name =~ "*PS TAP*"}
    {name =~ "*DAP*"}
} {
    if {[catch {targets -set -nocase -filter $filter} result] == 0} {
        puts "INFO: Selected target with filter: $filter"
        set selected 1
        break
    } else {
        puts "WARNING: Could not select target with filter '$filter': $result"
    }
}

if {$selected} {
    foreach reset_cmd {
        {rst -dap}
        {rst -system}
        {rst -por}
        {rst -srst}
    } {
        puts "INFO: Trying $reset_cmd"
        if {[catch $reset_cmd result] == 0} {
            puts "INFO: $reset_cmd succeeded"
        } else {
            puts "WARNING: $reset_cmd failed: $result"
        }
        after 1000
    }
}

after 3000
puts "AFTER_TARGETS_START"
targets
puts "AFTER_TARGETS_END"
