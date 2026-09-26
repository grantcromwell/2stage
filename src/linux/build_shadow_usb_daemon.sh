#!/bin/sh
set -eu
cd "$(dirname "$0")"
compiler=${ARM_LINUX_CC:-${CROSS_COMPILE:-arm-linux-gnueabihf-}gcc}
"$compiler" -std=c11 -O2 -Wall -Wextra -Werror -static shadow_usb_daemon.c -o shadow-usb-daemon
