connect
puts [targets]
targets 1
rst -dap
after 200
puts [targets]
targets -set -filter {name =~ "*Cortex-A9*#0"}
puts "SLCR_BEFORE [mrd -force 0xf800010c]"
mwr -force 0xf8000008 0xdf0d
puts "SLCR_UNLOCKED [mrd -force 0xf800010c]"
puts "SLCR_BOOT [mrd -force 0xf800025c]"
puts "CPU0 [rrd pc]"
disconnect
exit
