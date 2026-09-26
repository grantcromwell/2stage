#!/usr/bin/env bash

set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir/.."
backup=${RESIDENT_BACKUP_DIR:-$PWD/build/sd_backup_pre_resident}
mkdir -p "$PWD/build"
stage=$(mktemp -d "$PWD/build/resident_linux.XXXXXX")
sh linux/build_shadow_usb_daemon.sh
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror linux/test_shadow_usb_daemon.c -o "$stage/test_daemon"
"$stage/test_daemon"
dd if="$backup/ramdisk8M.uImage" of="$stage/rootfs.gz" bs=64 skip=1 status=none
gzip -dc "$stage/rootfs.gz" > "$stage/rootfs.ext2"
debugfs -R "dump /usr/local/bin/shadow-usb-daemon $stage/previous-daemon" "$stage/rootfs.ext2"
test -s "$stage/previous-daemon"
debugfs -R "dump /etc/init.d/rcS $stage/rcS" "$stage/rootfs.ext2"
rg -q '/usr/local/bin/shadow-usb-daemon /dev/ttyGS0' "$stage/rcS"
debugfs -w -R 'rm /usr/local/bin/shadow-usb-daemon' "$stage/rootfs.ext2"
debugfs -w -R "write $PWD/linux/shadow-usb-daemon /usr/local/bin/shadow-usb-daemon" "$stage/rootfs.ext2"
debugfs -w -R 'set_inode_field /usr/local/bin/shadow-usb-daemon mode 0100755' "$stage/rootfs.ext2"
debugfs -R "dump /usr/local/bin/shadow-usb-daemon $stage/verified-daemon" "$stage/rootfs.ext2"
cmp linux/shadow-usb-daemon "$stage/verified-daemon"


e2fsck -fy "$stage/rootfs.ext2" || test "$?" -eq 1
e2fsck -fn "$stage/rootfs.ext2"
gzip -n -9 -c "$stage/rootfs.ext2" > "$stage/ramdisk8M.image.gz"
mkimage -A arm -O linux -T ramdisk -C gzip -a 0x02000000 -e 0 -n shadow-resident -d "$stage/ramdisk8M.image.gz" "$stage/uRam"
cp "$stage/uRam" "$stage/ramdisk8M.uImage"
cmp "$stage/uRam" "$stage/ramdisk8M.uImage"
(
  cd "$stage"
  sha256sum uRam verified-daemon > SHA256SUMS
)
sha256sum "$stage/uRam" "$stage/verified-daemon"
printf 'Verified staging directory: %s\nNo SD writes performed.\n' "$stage"
