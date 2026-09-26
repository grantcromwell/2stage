#!/usr/bin/env bash


set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fpga_root=$(cd -- "$script_dir/.." && pwd)
source_dir="$fpga_root/build/zed_bootloader"
dtb="$fpga_root/build/zed_gadget_image/devicetree_ramdisk.dtb"
device=${SD_DEVICE:?set SD_DEVICE to the removable disk}
mount_point=${SD_MOUNT_POINT:?set SD_MOUNT_POINT to the mounted boot partition}

partition=${SD_PARTITION:?set SD_PARTITION to the boot partition device}
expected_serial=${SD_SERIAL:?set SD_SERIAL to the expected removable disk serial}
test -b "$device"
test -b "$partition"
test "$(lsblk -dn -o PKNAME "$partition")" = "$(basename -- "$device")"
test "$(lsblk -dn -o RM "$device")" = 1
test "$(lsblk -dn -o SERIAL "$device")" = "$expected_serial"
test "$(findmnt -no SOURCE "$mount_point")" = "$partition"
test -f "$source_dir/BOOT.BIN"; test -f "$source_dir/uImage"
test -f "$source_dir/ramdisk8M.uImage"; test -f "$dtb"
test -f "$source_dir/uRam"
for name in BOOT.BIN uImage ramdisk8M.uImage uRam; do
  cp "$source_dir/$name" "$mount_point/$name.new"
done
cp "$dtb" "$mount_point/devicetree_ramdisk.dtb.new"
sync
for name in BOOT.BIN uImage ramdisk8M.uImage uRam devicetree_ramdisk.dtb; do
  mv -f "$mount_point/$name.new" "$mount_point/$name"
done
sync
for name in BOOT.BIN uImage ramdisk8M.uImage uRam; do
  cmp "$source_dir/$name" "$mount_point/$name"
done
cmp "$dtb" "$mount_point/devicetree_ramdisk.dtb"
sha256sum "$source_dir/BOOT.BIN" "$source_dir/uImage" "$source_dir/ramdisk8M.uImage" "$dtb"
sha256sum "$mount_point/BOOT.BIN" "$mount_point/uImage" "$mount_point/ramdisk8M.uImage" "$mount_point/devicetree_ramdisk.dtb"
printf 'BOOTLOADER FLASH COMPLETE: %s updated; original SD contents remain in %s\n' "$device" "$fpga_root/build/sd_backup_20260913"
