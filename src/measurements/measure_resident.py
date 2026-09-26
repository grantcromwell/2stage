#!/usr/bin/env python3
"""Measure resident matrices/batches; never confuse amortized time with latency."""
import argparse
import json
import math
import statistics
import struct
import time
import zlib
from pathlib import Path
from measure_serial import Serial, vectors, summary


def exchange(link, command, payload, count=1):
    request = command + payload + struct.pack('<I', zlib.crc32(payload))
    start = time.perf_counter_ns()
    link.write(request)
    raw = link.read(136 * count)
    elapsed = time.perf_counter_ns() - start
    responses = []
    for offset in range(0, len(raw), 136):
        block = raw[offset:offset + 136]
        words = struct.unpack('<34I', block)
        assert words[0] == 0x31444853
        assert zlib.crc32(block[:132]) == words[33]
        assert not words[1] & 0xe0000000, words[:7]
        responses.append(words)
    return elapsed, responses


def upload(link, case):
    return exchange(link, b'M', struct.pack('<577I', case[0], *case[4]))


def batch(link, cases):
    payload = struct.pack('<I', len(cases))
    payload += b''.join(struct.pack('<24I', *case[5]) for case in cases)
    elapsed, responses = exchange(link, b'B', payload, len(cases))
    for case, w in zip(cases, responses):
        n, sat, err, q, _, _, y = case
        assert w[1] & 4 and bool(w[1] & 8) == bool(err)
        assert bool(w[1] & 16) == bool(sat)
        assert w[2] == 5*n*n + 10*n + 29
        assert list(w[7:31]) == y and w[31] | (w[32] << 32) == q
    return elapsed, responses


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--port', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--repeats', type=int, default=1000)
    args = p.parse_args()
    if args.repeats < 1:
        p.error('repeats must be positive')
    root = Path(__file__).resolve().parent
    cases = list(vectors(root / 'testdata/shadow_vectors.txt'))
    link = Serial(args.port)
    result = {'path': 'Linux USB resident-matrix/batch HLS', 'batches': {},
              'warmups_per_batch': 5, 'matrix_upload_request_bytes': 2313,
              'matrix_upload_response_bytes': 136, 'dimension': 24,
              'timing': 'perf_counter_ns; excludes request packing and response checking'}
    try:
        passed = 0
        for case in cases:
            if case[2]:
                continue  
            upload(link, case)
            batch(link, [case])
            passed += 1
        result['valid_oracle_cases_passed'] = passed
        identity = [0] * 576
        for i in range(24):
            identity[24*i+i] = 65536
        distinct = []
        for j in range(64):
            signed = [((i*7+j*13) % 9 - 4) * 16384 for i in range(24)]
            vector = [v & 0xffffffff for v in signed]
            q = sum((v*v) >> 16 for v in signed)
            distinct.append((24, 0, 0, q, identity, vector, vector))
        upload(link, distinct[0])
        batch(link, distinct)
        result['distinct_vectors_in_one_batch_passed'] = len(distinct)
        case = cases[24]
        result['matrix_upload_ns'] = upload(link, case)[0]
        for count in (1, 4, 16, 64):
            work = [case] * count
            for _ in range(5):
                batch(link, work)
            start = time.perf_counter_ns()
            samples = [batch(link, work) for _ in range(args.repeats)]
            wall_ns = time.perf_counter_ns() - start
            raw = [s[0] for s in samples]
            stats = summary([v/1000 for v in raw])
            stats['p99'] = sorted(raw)[math.ceil(.99*len(raw))-1]/1000
            result['batches'][str(count)] = {
                'batch_rtt_us': stats, 'raw_batch_rtt_ns': raw,
                'amortized_us_per_vector': statistics.mean(raw)/1000/count,
                'sustained_verified_vectors_per_second': args.repeats*count*1e9/wall_ns,
                'request_bytes': 9 + 96*count, 'response_bytes': 136*count,
                'raw_board_compute_ns': [[w[3] for w in ws] for _, ws in samples],
                'raw_board_transaction_ns': [[w[4] for w in ws] for _, ws in samples],
            }
            Path(args.output).write_text(json.dumps(result, indent=2)+'\n')
            print(count, stats, flush=True)
    finally:
        link.close()


if __name__ == '__main__':
    main()
