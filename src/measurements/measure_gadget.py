#!/usr/bin/env python3
"""Validate the Linux g_serial USB-device path against all HLS oracle vectors."""
import argparse
import json
import statistics
import struct
import time
import zlib
from pathlib import Path

from measure_serial import Serial, vectors, summary


def score(link, case):
    n, saturated, error, quadratic, matrix, vector, direction = case
    payload = struct.pack('<601I', n, *matrix, *vector)
    request = b'S' + payload + struct.pack('<I', zlib.crc32(payload))
    start = time.perf_counter_ns()
    link.write(request)
    raw = link.read(136)
    round_trip_ns = time.perf_counter_ns() - start
    if zlib.crc32(raw[:-4]) != struct.unpack_from('<I', raw, 132)[0]:
        raise AssertionError('USB response CRC mismatch')
    words = struct.unpack('<34I', raw)
    expected_cycles = 27 if error else 5 * n * n + 10 * n + 29
    assert words[0] == 0x31444853 and not words[1] & 0xc0000000, words[:7]
    assert bool(words[1] & 4) and bool(words[1] & 8) == bool(error), words[:7]
    assert bool(words[1] & 16) == bool(saturated), words[:7]
    assert words[2] == expected_cycles, (n, words[:7])
    assert list(words[7:31]) == direction, (n, 'direction mismatch')
    assert words[31] | words[32] << 32 == quadratic, (n, 'quadratic mismatch')
    assert words[6] == 1_000_000_000, words[:7]
    return round_trip_ns, words


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='/dev/ttyACM0')
    parser.add_argument('--output', default='usb_gadget_results.json')
    parser.add_argument('--repeats', type=int, default=100)
    args = parser.parse_args()
    link = Serial(args.port)
    try:
        link.write(b'P')
        hello = struct.unpack('<4I', link.read(16, 5))
        assert hello == (0x314e4542, 0x53484431, 1_000_000_000, 100_000_000), hello
        cases = list(vectors(Path(__file__).resolve().parent /
                             'testdata/shadow_vectors.txt'))
        for index, case in enumerate(cases):
            score(link, case)
            if (index + 1) % 10 == 0:
                print(f'USB gadget parity {index + 1}/80', flush=True)
        for _ in range(5):
            score(link, cases[24])
        samples = [score(link, cases[24]) for _ in range(args.repeats)]
        result = {
            'path': 'host USB CDC ACM -> Zynq Linux g_serial -> /dev/mem AXI -> Vitis HLS RTL',
            'parity_cases': len(cases),
            'oracle_max_absolute_error_lsb': 0,
            'oracle_rms_error_lsb': 0,
            'floating_point_error': 'not measured; parity reference is the fixed-point oracle',
            'warmup_requests': 5,
            'request_bytes': 2409,
            'response_bytes': 136,
            'dimension': cases[24][0],
            'round_trip_us': summary([t / 1000 for t, _ in samples]),
            'raw_round_trip_ns': [t for t, _ in samples],
            'samples': args.repeats,
            'full_request_rtt_us_mean': statistics.mean(t / 1000 for t, _ in samples),
            'board_compute_us_mean': statistics.mean(w[3] / 1000 for _, w in samples),
            'board_transaction_us_mean': statistics.mean(w[4] / 1000 for _, w in samples),
            'core_cycles': samples[0][1][2],
            'host_port': args.port,
        }
        Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    finally:
        link.close()


if __name__ == '__main__':
    main()
