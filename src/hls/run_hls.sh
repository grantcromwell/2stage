#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
vitis-run --mode hls --csim --config hls_config.cfg --work_dir build/config_flow
v++ --compile --mode hls --config hls_config.cfg --work_dir build/config_flow
vitis-run --mode hls --cosim --config hls_config.cfg --work_dir build/config_flow
vitis-run --mode hls --package --config hls_config.cfg --work_dir build/config_flow
