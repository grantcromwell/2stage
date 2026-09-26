connect
targets -set -filter {name =~ "APU"}

mwr 0xf8000008 0xdf0d
mwr 0xf8000900 0x0000000f

set before [lindex [mrd -value 0xf8000240] 0]
mwr 0xf8000240 [expr {$before & 0xfffffff0}]
mwr 0xf8000004 0x767b
puts "PL_SIGNATURE [mrd -force 0x43c0005c]"
puts "PL_STATUS [mrd -force 0x43c00004]"
puts "OCM_CONFIG [mrd 0xf8000910]"
puts "BOOT_PARK_CODE [mrd 0xffffff00 16]"
disconnect
exit
