#!/usr/bin/env python3
"""Send an explicitly supplied console command and collect UART output."""
import os
import sys
import time
import serial
port = os.environ.get('SERIAL_PORT')
if not port:
    raise SystemExit('Set SERIAL_PORT to the board UART device before running this script.')
with serial.Serial(port, 115200, timeout=0.2, exclusive=True) as uart:
    uart.write(('\r' + sys.argv[1] + '\r').encode())
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        data = uart.read(4096)
        if data:
            print(data.decode(errors='replace'), end='', flush=True)
