#pragma once
#include <cstdint>
#include <vector>


namespace cromwell::synth {
struct FixedPointMatrixResult {
    std::vector<int32_t> direction_raw;
    int64_t squared_distance_raw=0;
    bool saturated=false;
};
int32_t quantize_q16_16(double value,bool& saturated);
FixedPointMatrixResult score_q16_16(const std::vector<int32_t>& x,
    const std::vector<std::vector<int32_t>>& a);
bool fixed_point_matrix_self_test();
}
