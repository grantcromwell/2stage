#!/usr/bin/env bash


set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fpga_root=$(cd -- "$script_dir/.." && pwd)
backup="$fpga_root/build/sd_backup_20260913/BOOT.BIN"
image_dir="$fpga_root/build/zed_gadget_image"
out="$fpga_root/build/zed_bootloader"
cross=${CROSS_COMPILE:-arm-linux-gnueabihf-}
mkdir -p "$out"
test -f "$backup"; test -f "$image_dir/zImage"; test -f "$image_dir/ramdisk8M.image.gz"; test -f "$image_dir/devicetree_ramdisk.dtb"



dd if="$backup" of="$out/fsbl.bin" bs=1 skip=$((0xac0)) count=$((0x1532c)) status=none
dd if="$backup" of="$out/uboot.bin" bs=1 skip=$((0x3f1900)) count=$((0xb1d2 * 4)) status=none

old='sdboot=echo Copying Linux from SD to RAM...;mmcinfo;fatload mmc 0 0x8000 zImage;fatload mmc 0 0x1000000 devicetree_ramdisk.dtb;fatload mmc 0 0x800000 ramdisk8M.image.gz;go 0x8000'
new='sdboot=run sdboot_linaro;mmcinfo;fatload mmc 0 3000000 uImage;fatload mmc 0 2000000 uRam;fatload mmc 0 2a00000 devicetree_ramdisk.dtb;bootm 3000000 2000000 2a00000'
test "${#new}" -le "${#old}"
OLD="$old" NEW="$new" perl -0777 -i -pe '
  BEGIN {$old=$ENV{OLD}; $new=$ENV{NEW};}
  $count = s/\Q$old\E/$new . (" " x (length($old)-length($new)))/e;
  END { die "expected exactly one U-Boot sdboot environment\n" unless $count == 1; }
' "$out/uboot.bin"



OLD='sdboot_linaro=echo Copying Linux from SD to RAM...;mmcinfo;fatload mmc 0 0x8000 zImage;fatload mmc 0 0x1000000 devicetree_linaro.dtb;go 0x8000' \
NEW='sdboot_linaro=setenv bootm_low 8000000;setenv bootm_size 8000000' \
perl -0777 -i -pe 'BEGIN {$old=$ENV{OLD}; $new=$ENV{NEW}; die if length($new)>length($old)}
 $count=s/\Q$old\E/$new . (" " x (length($old)-length($new)))/e;
 END {die "alternate environment missing" unless $count==1}' "$out/uboot.bin"

"${cross}objcopy" -I binary -O elf32-littlearm -B arm --rename-section .data=.text,alloc,load,readonly,data,contents "$out/fsbl.bin" "$out/fsbl.o"
"${cross}ld" -Ttext 0 -e 0 -o "$out/fsbl.elf" "$out/fsbl.o"
"${cross}objcopy" -I binary -O elf32-littlearm -B arm --rename-section .data=.text,alloc,load,readonly,data,contents "$out/uboot.bin" "$out/u-boot.o"
"${cross}ld" -Ttext 0x04000000 -e 0x04000000 -o "$out/u-boot.elf" "$out/u-boot.o"
mkimage -A arm -O linux -T kernel -C none -a 0x8000 -e 0x8000 \
  -n shadow-linux -d "$image_dir/zImage" "$out/uImage"
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x2000000 -e 0 \
  -n shadow-rootfs -d "$image_dir/ramdisk8M.image.gz" "$out/ramdisk8M.uImage"
mkimage -l "$out/uImage" | grep -q 'Image Type:   ARM Linux Kernel Image'
mkimage -l "$out/ramdisk8M.uImage" | grep -q 'Image Type:   ARM Linux RAMDisk Image'
cp "$out/ramdisk8M.uImage" "$out/uRam"
cp "$fpga_root/build/shadow_accel_proj/shadow_accel_proj.runs/impl_1/shadow_accel_bd_wrapper.bit" "$out/shadow_accel.bit"
printf 'the_ROM_image:\n{\n  [bootloader] %s\n  %s\n  %s\n}\n' \
  "$out/fsbl.elf" "$out/shadow_accel.bit" "$out/u-boot.elf" > "$out/boot.bif"
bootgen -arch zynq -image "$out/boot.bif" -o "$out/BOOT.BIN" -w
test -s "$out/BOOT.BIN"
sha256sum "$out/BOOT.BIN" "$out/uImage" "$out/ramdisk8M.uImage" > "$out/SHA256SUMS"
printf 'Corrected bootloader build succeeded: %s\n' "$out/BOOT.BIN"
