connect
puts [targets]
targets -set -filter {name =~ "APU"}
foreach address {0xf8000100 0xf8000108 0xf800010c 0xf8000120 0xf800012c 0xf8000170 0xf8000178 0xf8000240 0xf8000258 0xf800025c 0xf8000900 0xf8000700 0xf8000704 0xe0001000 0xe0001004 0xe0001018 0xe000102c 0xe0001034} {
  if {[catch {mrd $address} value]} {puts "$address ERROR $value"} else {puts $value}
}
targets -set -filter {name =~ "*Cortex-A9*#0"}
stop
puts "CPU0_PC [rrd pc]"
puts "CPU0_CPSR [rrd cpsr]"
con
disconnect
exit
