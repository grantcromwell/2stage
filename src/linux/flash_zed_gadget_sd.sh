#!/usr/bin/env bash

set -euo pipefail
fpga_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image_dir="$fpga_root/build/zed_gadget_image"
mount_point=${SD_MOUNT_POINT:?set SD_MOUNT_POINT to the mounted boot partition}
device=${SD_DEVICE:?set SD_DEVICE to the removable disk}

partition=${SD_PARTITION:?set SD_PARTITION to the boot partition device}
expected_serial=${SD_SERIAL:?set SD_SERIAL to the expected removable disk serial}
test -b "$device"
test -b "$partition"
test "$(lsblk -dn -o PKNAME "$partition")" = "$(basename -- "$device")"
test "$(lsblk -ndo RM "$device")" = 1
test "$(lsblk -dn -o SERIAL "$device")" = "$expected_serial"
test "$(findmnt -n -o SOURCE --target "$mount_point")" = "$partition"
test -f "$image_dir/SHA256SUMS"
(cd "$image_dir" && sha256sum -c SHA256SUMS)



install -m 0644 "$image_dir/zImage" "$mount_point/zImage.new"
install -m 0644 "$image_dir/devicetree_ramdisk.dtb" "$mount_point/devicetree_ramdisk.dtb.new"
install -m 0644 "$image_dir/ramdisk8M.image.gz" "$mount_point/ramdisk8M.image.gz.new"
sync
mv -f "$mount_point/zImage.new" "$mount_point/zImage"
mv -f "$mount_point/devicetree_ramdisk.dtb.new" "$mount_point/devicetree_ramdisk.dtb"
mv -f "$mount_point/ramdisk8M.image.gz.new" "$mount_point/ramdisk8M.image.gz"
sync
sha256sum "$mount_point/zImage" "$mount_point/devicetree_ramdisk.dtb" \
  "$mount_point/ramdisk8M.image.gz"
printf 'FLASH COMPLETE: %s updated; original files remain in %s/build/sd_backup_20260913\n' "$device" "$fpga_root"
