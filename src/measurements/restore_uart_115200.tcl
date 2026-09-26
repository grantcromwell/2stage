connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
stop
mwr -force 0xe0001000 0x28
mwr -force 0xe0001004 0x20
mwr -force 0xe0001018 124
mwr -force 0xe0001034 6
mwr -force 0xe0001000 0x14
con
after 100
puts "UART restored to 115200 baud"
disconnect
exit
