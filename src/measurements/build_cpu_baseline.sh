#!/usr/bin/env bash

set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output_dir="$script_dir/../build/measurements"
mkdir -p "$output_dir"
"${CXX:-c++}" -O3 -std=c++14 -march=native -Wall -Wextra -Werror \
  "$script_dir/benchmark_cpu.cpp" "$script_dir/fixed_point_matrix.cpp" \
  -o "$output_dir/shadow_cpu_baseline"
printf 'Built %s\n' "$output_dir/shadow_cpu_baseline"
