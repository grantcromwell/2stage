open_hw_manager
connect_hw_server -allow_non_jtag
foreach target [get_hw_targets] {
  puts "TARGET: $target"
  current_hw_target $target
  open_hw_target
  foreach device [get_hw_devices] {puts "DEVICE: $device PART: [get_property PART $device]"}
  close_hw_target
}
close_hw_manager
