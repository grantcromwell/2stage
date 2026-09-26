#!/usr/bin/env python3
"""Test temporary U-Boot settings; never save environment or write the SD."""
import os
import subprocess
import time
from pathlib import Path
import serial

root = Path(__file__).resolve().parent
port = os.environ.get('SERIAL_PORT')
if not port:
    raise SystemExit('Set SERIAL_PORT to the board UART device before running this script.')
with serial.Serial(port, 115200, timeout=0.2, exclusive=True) as uart, (root / 'boot_console_test.log').open('wb', buffering=0) as log:
    def read_until(needle, seconds):
        data = b''
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            part = uart.read(4096)
            if part:
                log.write(part)
                print(part.decode(errors='replace'), end='', flush=True)
                data += part
                if needle and needle in data:
                    return
        if needle:
            raise TimeoutError(repr(needle))

    reset = subprocess.Popen(['xsdb', str(root / 'reboot_sd.tcl')], stdout=subprocess.DEVNULL)
    read_until(b'Hit any key', 40)
    uart.write(b' ')
    read_until(b'zed-boot> ', 10)
    for command in [
        'setenv fdt_high 0xffffffff',
        'setenv bootm_low 0x08000000',
        'setenv bootm_size 0x08000000',
        'setenv bootargs console=ttyPS0,115200 root=/dev/ram0 rw rootfstype=ext2 earlycon=cdns,mmio,0xe0001000 keep_bootcon clk_ignore_unused',
    ]:
        uart.write(command.encode() + b'\r')
        read_until(b'zed-boot> ', 10)
    uart.write(b'run sdboot\r')
    read_until(None, 150)
    reset.wait(timeout=5)
