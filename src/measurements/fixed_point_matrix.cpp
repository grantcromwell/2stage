#include "fixed_point_matrix.h"
#include <cmath>
#include <limits>
#include <stdexcept>
namespace cromwell::synth {
namespace {
int64_t scale(int64_t product) {
    
    return product/65536-(product<0 && product%65536!=0);
}
int32_t clamp(int64_t value,bool& saturated) {
    if(value>INT32_MAX){saturated=true;return INT32_MAX;}
    if(value<INT32_MIN){saturated=true;return INT32_MIN;}
    return static_cast<int32_t>(value);
}
}
int32_t quantize_q16_16(double value,bool& saturated) {
    if(!std::isfinite(value))throw std::invalid_argument("Nonfinite Q16 input");
    const double raw=std::round(value*65536.0);
    if(raw>INT32_MAX){saturated=true;return INT32_MAX;}
    if(raw<INT32_MIN){saturated=true;return INT32_MIN;}
    return static_cast<int32_t>(raw);
}
FixedPointMatrixResult score_q16_16(const std::vector<int32_t>& x,
 const std::vector<std::vector<int32_t>>& a) {
    const auto n=x.size();
    if(n<1||n>24||a.size()!=n)throw std::invalid_argument("Q16 dimension must be 1..24");
    for(const auto& row:a)if(row.size()!=n)throw std::invalid_argument("Q16 matrix must be square");
    FixedPointMatrixResult out;out.direction_raw.resize(n);
    for(size_t r=0;r<n;++r){int64_t sum=0;
        for(size_t c=0;c<n;++c)sum+=scale(int64_t(a[r][c])*x[c]);
        out.direction_raw[r]=clamp(sum,out.saturated);
    }
    for(size_t i=0;i<n;++i)out.squared_distance_raw+=scale(int64_t(x[i])*out.direction_raw[i]);
    return out;
}
bool fixed_point_matrix_self_test() {
    const auto result=score_q16_16({65536,-65536},{{65536,0},{0,65536}});
    return !result.saturated&&result.direction_raw==std::vector<int32_t>({65536,-65536})&&result.squared_distance_raw==131072;
}
}
