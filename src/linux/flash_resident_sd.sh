#!/usr/bin/env bash

set -euo pipefail
fpga_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage=${1:?pass verified resident_linux staging directory}
card=${SD_MOUNT_POINT:?set SD_MOUNT_POINT to the mounted boot partition}
device=${SD_DEVICE:?set SD_DEVICE to the removable disk}
backup=${RESIDENT_BACKUP_DIR:-$fpga_root/build/sd_backup_pre_resident}
test -d "$stage"
partition=${SD_PARTITION:?set SD_PARTITION to the boot partition device}
expected_serial=${SD_SERIAL:?set SD_SERIAL to the expected removable disk serial}
test -b "$device"
test -b "$partition"
test "$(lsblk -dn -o PKNAME "$partition")" = "$(basename -- "$device")"
test "$(lsblk -dn -o RM "$device")" = 1
test "$(lsblk -dn -o SERIAL "$device")" = "$expected_serial"
test "$(findmnt -no SOURCE "$card")" = "$partition"
test -f "$stage/SHA256SUMS"
(cd "$stage" && sha256sum -c SHA256SUMS)
cmp "$stage/uRam" "$stage/ramdisk8M.uImage"
cmp "$backup"/BOOT.BIN "$card/BOOT.BIN"
cmp "$backup"/uImage "$card/uImage"
cmp "$backup"/devicetree_ramdisk.dtb "$card/devicetree_ramdisk.dtb"
cp "$stage/ramdisk8M.uImage" "$card/ramdisk8M.uImage.new"
cp "$stage/uRam" "$card/uRam.new"
sync
cmp "$stage/ramdisk8M.uImage" "$card/ramdisk8M.uImage.new"
cmp "$stage/uRam" "$card/uRam.new"
mv -f "$card/ramdisk8M.uImage.new" "$card/ramdisk8M.uImage"
mv -f "$card/uRam.new" "$card/uRam"
sync
cmp "$stage/ramdisk8M.uImage" "$card/ramdisk8M.uImage"
cmp "$stage/uRam" "$card/uRam"
sha256sum "$card/uRam" "$card/ramdisk8M.uImage"
echo 'Verified both ramdisk aliases. Safe unmount is a separate command.'
