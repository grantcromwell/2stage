create_project -in_memory -part xc7z020clg484-1
set root [file normalize [file join [file dirname [info script]] ..]]
foreach source {shadow_core shadow_accelerator shadow_top} {
  read_vhdl -vhdl2008 $root/rtl/$source.vhd
}
synth_design -rtl -top shadow_top
