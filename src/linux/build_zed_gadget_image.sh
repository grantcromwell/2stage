#!/usr/bin/env bash


set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fpga_root=$(cd -- "$script_dir/.." && pwd)
kernel_dir="$fpga_root/build/linux_gadget/linux-6.12.109"
output_dir="$fpga_root/build/zed_gadget_image"
cross=${CROSS_COMPILE:-arm-linux-gnueabihf-}
old_ramdisk="$fpga_root/build/sd_backup_20260913/ramdisk8M.image.gz"
bitstream="$fpga_root/build/shadow_accel_proj/shadow_accel_proj.runs/impl_1/shadow_accel_bd_wrapper.bit"

test -d "$kernel_dir"
command -v "${cross}gcc" >/dev/null
test -f "$old_ramdisk"
test -f "$bitstream"
test -x "$script_dir/shadow-usb-daemon"
mkdir -p "$output_dir"

cp "$script_dir/shadow-zed-gadget.dts" "$kernel_dir/arch/arm/boot/dts/xilinx/"
dt_makefile="$kernel_dir/arch/arm/boot/dts/xilinx/Makefile"
if ! grep -q 'shadow-zed-gadget.dtb' "$dt_makefile"; then
  printf '\tdtb-y += shadow-zed-gadget.dtb\n' >> "$dt_makefile"
fi
make -C "$kernel_dir" ARCH=arm CROSS_COMPILE="$cross" multi_v7_defconfig
config_tool="$kernel_dir/scripts/config"
(cd "$kernel_dir" && "$config_tool" --enable USB_G_SERIAL --enable USB_U_SERIAL --enable USB_F_ACM \
  --enable USB_LIBCOMPOSITE --enable FPGA --enable FPGA_MGR_ZYNQ_FPGA \
  --enable RD_GZIP --enable EXT2_FS --disable USB_CHIPIDEA_HOST)
make -C "$kernel_dir" ARCH=arm CROSS_COMPILE="$cross" olddefconfig
make -C "$kernel_dir" ARCH=arm CROSS_COMPILE="$cross" -j"$(nproc)" zImage \
  xilinx/shadow-zed-gadget.dtb
cp "$kernel_dir/arch/arm/boot/zImage" "$output_dir/zImage"
cp "$kernel_dir/arch/arm/boot/dts/xilinx/shadow-zed-gadget.dtb" "$output_dir/devicetree_ramdisk.dtb"
cp "$old_ramdisk" "$output_dir/ramdisk16M.image.gz"
gzip -d -f "$output_dir/ramdisk16M.image.gz"
e2fsck -pf "$output_dir/ramdisk16M.image" || {
  fsck_status=$?
  test "$fsck_status" -eq 1
}
truncate -s 16M "$output_dir/ramdisk16M.image"
resize2fs "$output_dir/ramdisk16M.image" 16M

staging=$(mktemp -d /tmp/shadow-gadget-rootfs.XXXXXX)
trap 'rm -rf "$staging"' EXIT
cp "$script_dir/shadow-usb-daemon" "$staging/shadow-usb-daemon"
cp "$bitstream" "$staging/shadow_accel.bit"
cp "$output_dir/ramdisk16M.image" "$staging/rcS.orig.fs"
debugfs -R "dump -p /etc/init.d/rcS $staging/rcS.orig" "$staging/rcS.orig.fs" >/dev/null 2>&1
cat >> "$staging/rcS.orig" <<'EOF'

echo "++ Loading shadow HLS accelerator"
if [ -e /sys/class/fpga_manager/fpga0/firmware ]; then
    echo shadow_accel.bit > /sys/class/fpga_manager/fpga0/firmware || echo "FPGA load failed"
fi
echo "++ Starting USB CDC-ACM shadow gadget"
/usr/local/bin/shadow-usb-daemon /dev/ttyGS0 &
EOF
debugfs -w -R 'mkdir /usr/local' "$output_dir/ramdisk16M.image" >/dev/null 2>&1 || true
debugfs -w -R 'mkdir /usr/local/bin' "$output_dir/ramdisk16M.image" >/dev/null 2>&1 || true
debugfs -w -R 'mkdir /lib/firmware' "$output_dir/ramdisk16M.image" >/dev/null 2>&1 || true
debugfs -w -R "write $staging/shadow-usb-daemon /usr/local/bin/shadow-usb-daemon" "$output_dir/ramdisk16M.image" >/dev/null
debugfs -w -R 'set_inode_field /usr/local/bin/shadow-usb-daemon mode 0100755' "$output_dir/ramdisk16M.image" >/dev/null
debugfs -w -R "write $staging/shadow_accel.bit /lib/firmware/shadow_accel.bit" "$output_dir/ramdisk16M.image" >/dev/null
debugfs -w -R 'rm /etc/init.d/rcS' "$output_dir/ramdisk16M.image" >/dev/null
debugfs -w -R "write $staging/rcS.orig /etc/init.d/rcS" "$output_dir/ramdisk16M.image" >/dev/null
debugfs -w -R 'set_inode_field /etc/init.d/rcS mode 0100755' "$output_dir/ramdisk16M.image" >/dev/null
gzip -9 -c "$output_dir/ramdisk16M.image" > "$output_dir/ramdisk8M.image.gz"
rm "$output_dir/ramdisk16M.image"
dtc -I dtb -O dts "$output_dir/devicetree_ramdisk.dtb" > "$output_dir/devicetree_ramdisk.dts"
grep -q 'dr_mode = "peripheral"' "$output_dir/devicetree_ramdisk.dts"
grep -q 'accelerator@43c00000' "$output_dir/devicetree_ramdisk.dts"
test "$(stat -c %s "$output_dir/ramdisk8M.image.gz")" -lt 8388608
sha256sum "$output_dir/zImage" "$output_dir/devicetree_ramdisk.dtb" \
  "$output_dir/ramdisk8M.image.gz" > "$output_dir/SHA256SUMS"
printf 'Build succeeded. Run flash_zed_gadget_sd.sh only after reviewing SHA256SUMS.\n'
