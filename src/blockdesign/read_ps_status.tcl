connect
puts [targets]
targets -set -filter {name =~ "APU"}
puts "IO_PLL_CTRL"
puts [mrd 0xf8000108]
puts "FPGA0_CLK_CTRL"
puts [mrd 0xf8000170]
puts "FPGA_RST_CTRL"
puts [mrd 0xf8000240]
puts "SHADOW_SIGNATURE"
if {[catch {mrd 0x43c0005c} shadow_probe_error]} {puts "SIGNATURE_UNAVAILABLE: $shadow_probe_error"} else {puts $shadow_probe_error}
disconnect
exit
