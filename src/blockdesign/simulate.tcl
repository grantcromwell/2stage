set shadow_fpga_root [file normalize [file join [file dirname [info script]] ..]]
create_project -force shadow_sim $shadow_fpga_root/build/sim -part xc7z020clg484-1
set hls_vhdl [glob -nocomplain $shadow_fpga_root/hls/build/config_flow/hls/syn/vhdl/*.vhd]
if {[llength $hls_vhdl] == 0} {error "Run Vitis HLS synthesis before simulating"}
foreach source $hls_vhdl {
  add_files -norecurse $source
  set_property file_type {VHDL 2008} [get_files $source]
}
foreach rtl {hls_shadow_core shadow_accelerator shadow_top} {
  add_files $shadow_fpga_root/rtl/$rtl.vhd
  set_property file_type {VHDL 2008} [get_files $shadow_fpga_root/rtl/$rtl.vhd]
}
add_files -fileset sim_1 $shadow_fpga_root/rtl/tb_shadow_accelerator.sv
add_files -fileset sim_1 $shadow_fpga_root/hls/build/config_flow/hls/csim/build/shadow_vectors.txt
set_property top tb_shadow_accelerator [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set shadow_pass_file $shadow_fpga_root/build/sim/shadow_sim.sim/sim_1/behav/xsim/shadow_test_pass.txt
file delete -force $shadow_pass_file
launch_simulation
close_sim
if {![file exists $shadow_pass_file]} {error "Simulation did not reach the PASS marker"}
