# Generate a PS-only hardware handoff for Vitis standalone firmware.  The
# accelerator remains at 0x43C00000 in the separately programmed PL image.
set fpga_root [file normalize [file join [file dirname [info script]] ..]]
file mkdir $fpga_root/reports
set board [get_board_parts -quiet digilentinc.com:zedboard:part0:*]
if {[llength $board] != 1} {error "ZedBoard board files are required"}
set target_part [get_property PART_NAME $board]
create_project -force shadow_usb_ps_proj $fpga_root/build/shadow_usb_ps_proj -part $target_part
set_property board_part $board [current_project]
create_bd_design shadow_usb_ps_bd
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
set_property -dict [list CONFIG.PCW_EN_USB0 {1} CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} CONFIG.PCW_USE_M_AXI_GP0 {0}] $ps
validate_bd_design
save_bd_design
generate_target all [get_files shadow_usb_ps_bd.bd]
write_hw_platform -fixed -force -file $fpga_root/reports/shadow_usb_ps.xsa
