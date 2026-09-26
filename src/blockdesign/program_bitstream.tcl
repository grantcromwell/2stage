set shadow_fpga_root [file normalize [file join [file dirname [info script]] ..]]
set shadow_bit $shadow_fpga_root/build/shadow_accel_proj/shadow_accel_proj.runs/impl_1/shadow_accel_bd_wrapper.bit
if {![file exists $shadow_bit]} {error "No bitstream found"}
open_hw_manager
connect_hw_server -allow_non_jtag
set shadow_target_query *
if {[info exists ::env(SHADOW_JTAG_TARGET)]} {set shadow_target_query "*/$::env(SHADOW_JTAG_TARGET)"}
set shadow_target [get_hw_targets -quiet $shadow_target_query]
if {[llength $shadow_target] != 1} {error "Set SHADOW_JTAG_TARGET or connect exactly one JTAG target"}
current_hw_target $shadow_target
open_hw_target
set shadow_device [get_hw_devices -quiet xc7z020*]
if {[llength $shadow_device] != 1} {error "Expected exactly one XC7Z020"}
set_property PROGRAM.FILE $shadow_bit $shadow_device
program_hw_devices $shadow_device
refresh_hw_device $shadow_device
report_property $shadow_device
close_hw_target
close_hw_manager
