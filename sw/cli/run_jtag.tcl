# Program the ZUBoard bitstream and run the BNN bare-metal ELF over JTAG.
#
# Required environment variables:
#   BNN_BIT       Absolute path to .bit
#   BNN_ELF       Absolute path to app .elf
#   BNN_PSU_INIT  Absolute path to psu_init.tcl from the Vivado handoff

proc env_path {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing environment variable: $name"
  }

  set value [file normalize $::env($name)]
  if {![file exists $value]} {
    error "$name path does not exist: $value"
  }
  return $value
}

proc try_target {filter description} {
  set status [catch {
    targets -set -nocase -filter $filter
  } result]

  if {$status != 0} {
    puts "WARNING: Could not select $description target with filter '$filter': $result"
    return 0
  }

  puts "INFO: Selected $description target"
  return 1
}

set bit_file [env_path BNN_BIT]
set elf_file [env_path BNN_ELF]
set psu_init_tcl [env_path BNN_PSU_INIT]

puts "INFO: Bitstream: $bit_file"
puts "INFO: ELF      : $elf_file"
puts "INFO: PS init  : $psu_init_tcl"

connect
after 1000

puts "INFO: Available JTAG targets:"
targets

# Reset and initialize the PS, then program PL and run the app on A53 #0.
try_target {name =~ "*APU*"} "APU"
catch {rst -system}
after 3000

if {![try_target {name =~ "*PSU*"} "PSU"]} {
  error "Could not find the Zynq UltraScale+ PSU target. Check J16 micro-USB/JTAG connection and board power."
}

source $psu_init_tcl
psu_init

fpga -file $bit_file

catch {psu_ps_pl_isolation_removal}
catch {psu_ps_pl_reset_config}

if {![try_target {name =~ "*Cortex-A53 #0*"} "Cortex-A53 #0"]} {
  error "Could not find Cortex-A53 #0 target after PS initialization."
}

catch {stop}
rst -processor
dow $elf_file
con

puts "INFO: BNN demo is running. Watch the UART terminal for PASS/FAIL output."
