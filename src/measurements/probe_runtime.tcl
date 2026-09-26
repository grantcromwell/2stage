connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
puts "CPU0 [rrd pc]"
puts "MAILBOX [mrd -force 0x0002d000 3]"
puts "UART_CR [mrd -force 0xe0001000]"
puts "UART_MR [mrd -force 0xe0001004]"
puts "UART_BAUDGEN [mrd -force 0xe0001018]"
puts "UART_SR [mrd -force 0xe000102c]"
puts "UART_BAUDDIV [mrd -force 0xe0001034]"
puts "UART_CLK [mrd -force 0xf8000154]"
disconnect
exit
