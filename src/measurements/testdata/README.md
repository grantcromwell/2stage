The 80 cases in `shadow_vectors.txt` were copied from the existing Vitis HLS
C-simulation output. They include expected fixed-point results, saturation flags,
and invalid-dimension cases. CPU and board measurement clients use this fixture
without requiring a local Vitis build.

Regenerate with `bash src/hls/run_hls.sh` from the repository root, then compare
`src/hls/build/config_flow/hls/csim/build/shadow_vectors.txt` with this fixture
before updating it. The generator is `src/hls/test_shadow_hls.cpp`.
