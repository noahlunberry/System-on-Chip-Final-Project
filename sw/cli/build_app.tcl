# Build the ZUBoard BNN bare-metal app with classic XSCT project commands.
#
# Required environment variables:
#   BNN_REPO_ROOT        Repository root
#   BNN_VITIS_WORKSPACE  Workspace output directory
#   BNN_XSA              Hardware platform XSA

proc env_or_error {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing environment variable: $name"
  }
  return [file normalize $::env($name)]
}

proc checked_path {path description} {
  if {![file exists $path]} {
    error "$description not found: $path"
  }
}

set repo_root [env_or_error BNN_REPO_ROOT]
set workspace [env_or_error BNN_VITIS_WORKSPACE]
set xsa_file [env_or_error BNN_XSA]
set src_dir [file join $repo_root sw src]
set app_name "bnn_fcc_demo"

checked_path $repo_root "Repository root"
checked_path $xsa_file "XSA hardware platform"
checked_path $src_dir "Software source directory"

puts "INFO: Repository: $repo_root"
puts "INFO: Workspace : $workspace"
puts "INFO: XSA       : $xsa_file"
puts "INFO: Sources   : $src_dir"

file mkdir $workspace
setws $workspace

set existing_apps [list]
catch {set existing_apps [app list]}
if {[lsearch -exact $existing_apps $app_name] >= 0} {
  app remove $app_name
}

app create \
  -name $app_name \
  -hw $xsa_file \
  -proc psu_cortexa53_0 \
  -os standalone \
  -lang C++ \
  -template {Empty Application}

importsources -name $app_name -path $src_dir
app build -name $app_name

set elf_candidates [glob -nocomplain -types f \
  [file join $workspace $app_name Debug "${app_name}.elf"] \
  [file join $workspace $app_name Release "${app_name}.elf"] \
  [file join $workspace $app_name "**" "${app_name}.elf"]]

if {[llength $elf_candidates] == 0} {
  error "Build completed, but ${app_name}.elf was not found under $workspace"
}

set elf_file [lindex $elf_candidates 0]
puts "INFO: ELF: $elf_file"

set artifact_file [file join $workspace "bnn_fcc_demo_artifacts.txt"]
set fd [open $artifact_file w]
puts $fd "workspace=$workspace"
puts $fd "xsa=$xsa_file"
puts $fd "elf=$elf_file"
close $fd
puts "INFO: Artifacts: $artifact_file"
