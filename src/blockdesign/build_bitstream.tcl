set shadow_fpga_root [file normalize [file join [file dirname [info script]] ..]]
file mkdir $shadow_fpga_root/reports
set shadow_constraints [file join $shadow_fpga_root constraints shadow_accelerator.xdc]
if {![file exists $shadow_constraints]} {error "Missing required constraints file: $shadow_constraints"}
open_project $shadow_fpga_root/build/shadow_accel_proj/shadow_accel_proj.xpr
add_files -fileset constrs_1 $shadow_constraints
set_property PROCESSING_ORDER LATE [get_files shadow_accelerator.xdc]
# One synthesis process avoids simultaneous high memory use on this host.
set_param general.maxThreads 2
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file $shadow_fpga_root/reports/synth_utilization.rpt
close_design
launch_runs impl_1 -to_step route_design -jobs 1
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -hierarchical -file $shadow_fpga_root/reports/routed_utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file $shadow_fpga_root/reports/routed_timing.rpt
report_drc -file $shadow_fpga_root/reports/routed_drc.rpt
report_clocks -file $shadow_fpga_root/reports/clocks.rpt
set worst_setup [get_timing_paths -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -delay_type min -max_paths 1]
if {[get_property SLACK $worst_setup] < 0 || [get_property SLACK $worst_hold] < 0} {error "Timing failed; bitstream withheld"}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Bitstream generation failed"}
open_run impl_1
write_hw_platform -fixed -include_bit -force -file $shadow_fpga_root/reports/shadow_accel.xsa
