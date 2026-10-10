set shadow_fpga_root [file normalize [file join [file dirname [info script]] ..]]
file mkdir $shadow_fpga_root/reports
proc InstallVectors {shadow_fpga_root} {
  exec bash [file join $shadow_fpga_root hls generate-vectors.sh]
}
InstallVectors $shadow_fpga_root
open_checkpoint $shadow_fpga_root/build/shadow_accel_proj/shadow_accel_proj.runs/shadow_accel_bd_shadow_accel_0_synth_1/shadow_accel_bd_shadow_accel_0.dcp
write_verilog -force -mode funcsim -rename_top shadow_top_post_synth $shadow_fpga_root/reports/shadow_post_synth.v
close_design
create_project -force shadow_netlist_sim $shadow_fpga_root/build/netlist_sim -part xc7z020clg484-1
add_files $shadow_fpga_root/reports/shadow_post_synth.v
add_files -fileset sim_1 $shadow_fpga_root/rtl/tb_shadow_accelerator.sv
add_files -fileset sim_1 $shadow_fpga_root/measurements/testdata/shadow_vectors.txt
set_property verilog_define {SHADOW_DUT_MODULE=shadow_top_post_synth} [get_filesets sim_1]
set_property top tb_shadow_accelerator [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set shadow_pass_file $shadow_fpga_root/build/netlist_sim/shadow_netlist_sim.sim/sim_1/behav/xsim/shadow_test_pass.txt
file delete -force $shadow_pass_file
launch_simulation
close_sim
if {![file exists $shadow_pass_file]} {error "Simulation did not reach the PASS marker"}
