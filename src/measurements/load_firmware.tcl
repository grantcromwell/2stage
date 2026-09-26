set shadow_measure_root [file dirname [file normalize [info script]]]
connect
foreach cpu {0 1} {
  targets -set -filter [format {name =~ "*Cortex-A9*#%d"} $cpu]
  
  catch {stop}
  set pc [rrd pc]
  puts "CPU$cpu $pc"
  regexp {pc: ([0-9a-fA-F]+)} $pc -> value
  scan $value %x pc_value
  if {$pc_value < 0xffff0000} {con; error "CPU is not in the observed boot park region; initialization withheld"}
}
targets -set -filter {name =~ "APU"}
set shadow_init [file normalize $shadow_measure_root/../build/shadow_accel_proj/shadow_accel_proj.gen/sources_1/bd/shadow_accel_bd/ip/shadow_accel_bd_ps7_0/ps7_init.tcl]
source $shadow_init

ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_post_config
puts "FCLK0 [mrd 0xf8000170]"
puts "ARM_CLOCK [mrd 0xf8000120]"
puts "IO_PLL [mrd 0xf8000108]"
puts "SIGNATURE [mrd -force 0x43c0005c]"
targets -set -filter {name =~ "*Cortex-A9*#0"}
dow $shadow_measure_root/firmware.elf
con
after 300
puts "FIRMWARE_MAILBOX [mrd -force 0x0002d000 3]"
disconnect
exit
