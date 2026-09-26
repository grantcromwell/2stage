

set fpga_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists shadow_board_part]} {
  set shadow_board_part digilentinc.com:zedboard:part0:*
}
set board [get_board_parts -quiet $shadow_board_part]
if {[llength $board] != 1} {error "Install board files for $shadow_board_part"}
set target_part [get_property PART_NAME $board]
create_project -force shadow_accel_proj $fpga_root/build/shadow_accel_proj -part $target_part
set_property board_part $board [current_project]
set hls_vhdl [glob -nocomplain $fpga_root/hls/build/config_flow/hls/syn/vhdl/*.vhd]
if {[llength $hls_vhdl] == 0} {error "Run bash src/hls/run_hls.sh before creating the Vivado project"}
foreach source $hls_vhdl {
  add_files -norecurse $source
  set_property file_type {VHDL 2008} [get_files $source]
}
foreach rtl {hls_shadow_core shadow_accelerator shadow_top} {
  add_files -norecurse $fpga_root/rtl/$rtl.vhd
  set_property file_type {VHDL 2008} [get_files $fpga_root/rtl/$rtl.vhd]
}
update_compile_order -fileset sources_1
create_bd_design shadow_accel_bd
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_EN_USB0 {1} CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1}] $ps
create_bd_cell -type module -reference shadow_top shadow_accel
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] [get_bd_cells axi_interconnect_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100m

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins shadow_accel/s_axi]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi_interconnect_0/ACLK] [get_bd_pins axi_interconnect_0/S00_ACLK] [get_bd_pins axi_interconnect_0/M00_ACLK] [get_bd_pins shadow_accel/fclk_clk0] [get_bd_pins rst_ps7_100m/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_100m/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_100m/interconnect_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100m/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins shadow_accel/fclk_reset0_n]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_locked
set_property CONFIG.CONST_VAL {1} [get_bd_cells reset_locked]
connect_bd_net [get_bd_pins reset_locked/dout] [get_bd_pins rst_ps7_100m/dcm_locked]
connect_bd_net [get_bd_pins shadow_accel/irq_f2p] [get_bd_pins ps7/IRQ_F2P]
assign_bd_address -offset 0x43C00000 -range 4K -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs shadow_accel/s_axi/reg0] -force
validate_bd_design
save_bd_design
generate_target all [get_files shadow_accel_bd.bd]
set wrapper [make_wrapper -files [get_files shadow_accel_bd.bd] -top]
add_files -norecurse $wrapper
set_property top shadow_accel_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
