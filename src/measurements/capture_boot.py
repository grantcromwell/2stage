#!/usr/bin/env python3
"""Capture one UART stream without competing readers; keep a persistent log."""
import os
import time
import serial
from pathlib import Path

port = os.environ.get('SERIAL_PORT')
if not port:
    raise SystemExit('Set SERIAL_PORT to the board UART device before running this script.')
deadline = time.monotonic() + 180
log = Path(__file__).resolve().parent / 'boot_console_latest.log'
with log.open('ab', buffering=0) as out:
    while time.monotonic() < deadline:
        try:
            with serial.Serial(port, 115200, timeout=0.5, exclusive=True) as uart:
                print('UART attached', flush=True)
                while time.monotonic() < deadline:
                    data = uart.read(4096)
                    if data:
                        out.write(data)
                        print(data.decode('utf-8', errors='replace'), end='', flush=True)
        except serial.SerialException as exc:
            print(f'UART reconnect: {exc}', flush=True)
            time.sleep(1)
