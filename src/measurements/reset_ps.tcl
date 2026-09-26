connect
targets -set -filter {name =~ "APU"}
puts "Asserting the board JTAG SRST pin"
rst -srst
after 1000
disconnect


connect
after 500
puts [targets]
targets -set -filter {name =~ "*Cortex-A9*#0"}
stop
puts "CPU0 [rrd pc]"
puts "PLL_STATUS [mrd -force 0xf800010c]"
puts "BOOT_MODE [mrd -force 0xf800025c]"
puts "FPGA_CLK [mrd -force 0xf8000170]"
disconnect
exit
