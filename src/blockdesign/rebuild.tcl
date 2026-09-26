set shadow_scripts [file dirname [file normalize [info script]]]
source $shadow_scripts/create_bd.tcl
close_project
source $shadow_scripts/build_bitstream.tcl
