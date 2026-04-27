# Probe the BNN AXI-Lite register block from XSCT/JTAG.

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set base [env_or_default BNN_BASE 0xA0000000]

connect -url TCP:127.0.0.1:3121
after 1000

puts "INFO: Available targets:"
targets

if {[catch {targets -set -nocase -filter {name =~ "*PSU*"}} result]} {
  puts "WARNING: Could not select PSU target: $result"
  targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
  catch {stop}
}

puts [format "INFO: Probing BNN MMIO base %s" $base]
puts "STATUS:"
mrd -force [expr {$base + 0x04}]
puts "CYCLE_COUNT:"
mrd -force [expr {$base + 0x28}]
puts "CONTROL reset/clear write:"
mwr -force [expr {$base + 0x00}] 0x0000000f
puts "STATUS after reset:"
mrd -force [expr {$base + 0x04}]
