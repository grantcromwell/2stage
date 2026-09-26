connect
puts [targets]
foreach target_filter {{name =~ "APU"} {name =~ "*Cortex-A9*#0"}} {
 targets -set -filter $target_filter
 puts "TARGET $target_filter"
 foreach addr {0xf8007080 0xf8000100 0xf800010c 0xf8000170 0xf800025c 0xfffffff0} {if {[catch {mrd -force $addr} v]} {puts $v} else {puts $v}}
}
disconnect
exit
