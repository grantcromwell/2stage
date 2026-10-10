#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
installVectors() {
  local vector_file
  vitis-run --mode hls --csim --config hls_config.cfg --work_dir build/config_flow
  vector_file=$(find build/config_flow -type f -name shadow_vectors.txt -print -quit)
  if [[ -z "$vector_file" && -f shadow_vectors.txt ]]; then
    vector_file=shadow_vectors.txt
  fi
  if [[ -z "$vector_file" ]]; then
    printf '%s\n' "HLS C simulation did not produce shadow_vectors.txt" >&2
    return 1
  fi
  mkdir -p ../measurements/testdata
  cp "$vector_file" ../measurements/testdata/shadow_vectors.txt
}
installVectors
