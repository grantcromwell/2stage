#!/bin/sh

set -eu
if [ ! -d /sys/class/udc ] || [ -z "$(ls -A /sys/class/udc)" ]; then
    echo 'No USB device controller: verify DT dr_mode, ChipIdea UDC, PHY and boot image' >&2
    exit 1
fi
modprobe g_serial use_acm=1
if [ ! -e /dev/ttyGS0 ]; then
    echo 'g_serial did not create /dev/ttyGS0' >&2
    exit 1
fi
exec /usr/local/bin/shadow-usb-daemon /dev/ttyGS0
