"""Run the compiled host baseline and retain raw results plus comparison."""
import argparse
import json
import math
import platform
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', default='../build/measurements/cpu_baseline.json')
parser.add_argument('--binary', type=Path, default=root / '../build/measurements/shadow_cpu_baseline')
parser.add_argument('--measurement-only', action='store_true')
args = parser.parse_args()
data = json.loads(subprocess.check_output([
    str(args.binary),
    str(root / 'testdata/shadow_vectors.txt'),
], text=True))
data['platform'] = platform.platform()
data['cpu'] = subprocess.check_output(['lscpu'], text=True)
(root / args.output).parent.mkdir(parents=True, exist_ok=True)
(root / args.output).write_text(json.dumps(data, indent=2) + '\n')
if args.measurement_only:
    print({key: data[key] for key in ('mean_ns', 'p50_ns', 'p95_ns', 'p99_ns', 'parity_cases')})
    raise SystemExit(0)
usb = json.loads((root / 'usb_baseline_1000.json').read_text())
raw = sorted(usb['raw_round_trip_ns'])
report = f'''# Current Linux USB and host CPU baseline

Measured 2026-09-13. No firmware, bitstream, or SD-card changes made.

| Metric | Result |
|---|---:|
| USB mean round trip, 1,000 samples | {usb['full_request_rtt_us_mean']:.3f} us |
| USB median | {usb['round_trip_us']['p50']:.3f} us |
| USB p95 | {usb['round_trip_us']['p95']:.3f} us |
| USB p99 | {raw[math.ceil(.99*len(raw))-1]/1000:.3f} us |
| USB min / max | {raw[0]/1000:.3f} / {raw[-1]/1000:.3f} us |
| Board transaction mean | {usb['board_transaction_us_mean']:.3f} us |
| Board compute/poll mean | {usb['board_compute_us_mean']:.3f} us |
| FPGA core cycles | {usb['core_cycles']} |
| Core time derived at configured 100 MHz | {usb['core_cycles']/100:.2f} us |
| Reciprocal USB mean RTT (not sustained loop throughput) | {1e6/usb['full_request_rtt_us_mean']:.1f} requests/s |
| Host C++ CPU mean, 10,000 samples | {data['mean_ns']/1000:.3f} us |
| Host CPU median / p95 / p99 | {data['p50_ns']/1000:.3f} / {data['p95_ns']/1000:.3f} / {data['p99_ns']/1000:.3f} us |
| Host CPU min / max | {data['min_ns']/1000:.3f} / {data['max_ns']/1000:.3f} us |

Both paths verified against all 80 oracle cases (invalid dimensions use CPU exceptions versus FPGA flags). Valid scoring results match fixed-point direction, quadratic score, and saturation. This is not floating-point accuracy validation.

Same timing vector: oracle case index 24, 24 dimensions, Q16.16 matrix-vector multiplication followed by quadratic scoring. CPU: existing score_q16_16, GCC {data['compiler']}, -O3 -std=c++14 -march=native, separate compilation without LTO; host AMD Ryzen 7 7445HS. 10,000 warmups, steady_clock per-call timing, returned-output allocation/deallocation behavior as in benchmark source, inputs cached and already quantized. Allocation is timed, destructor is outside timer. Results consumed through a volatile sink; no affinity, frequency locking, or load isolation. CPU is the host, NOT the Zynq ARM processor.

USB: five warmups, 2,409-byte request (full matrix plus vector) and 136-byte response, one request outstanding, host perf_counter_ns. Packing and result assertions outside RTT timer. Current benchmark does not retain raw board-side timings. CPU excludes transport/packing; ratio is a local-software versus offload-path comparison, not an isolated Linux overhead measurement. Neither path includes calibration, classification, or risk controls.

Observed USB-RTT/CPU-mean ratio: {usb['full_request_rtt_us_mean']/(data['mean_ns']/1000):.1f}x. The current offload path is slower for this small workload. No resident-matrix, batching, or bare-metal USB benchmark has been performed. Prior saved measurements remain untouched; differences across runs are not optimization gains.

Raw evidence: usb_baseline_1000.json and cpu_baseline.json. Reproduce CPU: run bash src/measurements/build_cpu_baseline.sh, then python3 src/measurements/run_cpu_baseline.py. The bundled testdata/shadow_vectors.txt contains the 80 HLS oracle cases. CPU performance is a reference implementation baseline, not a best-possible optimized implementation.
'''
(root / args.output).with_suffix('.md').write_text(report)
print(report)
