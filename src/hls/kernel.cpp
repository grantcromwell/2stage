#include "shadow_hls.hpp"
void shadow_hls(const ap_int<32> matrix[576], const ap_int<32> vector[24],
                ap_uint<5> dim, ap_int<32> direction[24],
                ap_int<64>& quadratic, ap_uint<1>& saturated,
                ap_uint<1>& error) {
#pragma HLS INTERFACE mode=ap_memory port=matrix
#pragma HLS INTERFACE mode=ap_memory port=vector
#pragma HLS INTERFACE mode=ap_memory port=direction
#pragma HLS INTERFACE mode=ap_ctrl_hs port=return
    saturated = 0;
    error = (dim == 0 || dim > SHADOW_DIM);
    quadratic = 0;
    ap_int<32> y[24];
    for (int i = 0; i < SHADOW_DIM; ++i) {
        y[i] = 0;
        direction[i] = 0;
    }
    if (error) return;
    rows: for (int r = 0; r < dim; ++r) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=24
        ap_int<64> sum = 0;
        cols: for (int c = 0; c < dim; ++c) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=24
#pragma HLS PIPELINE off
            ap_int<64> product = matrix[r * SHADOW_DIM + c] * vector[c];
#pragma HLS BIND_OP variable=product op=mul impl=dsp latency=3
            sum += product >> 16;
        }
        if (sum > 2147483647LL) { y[r] = 2147483647; saturated = 1; }
        else if (sum < -2147483648LL) { y[r] = -2147483648LL; saturated = 1; }
        else y[r] = sum;
        direction[r] = y[r];
    }
    ap_int<64> q = 0;
    dot: for (int i = 0; i < dim; ++i) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=24
#pragma HLS PIPELINE off
        ap_int<64> product = vector[i] * y[i];
#pragma HLS BIND_OP variable=product op=mul impl=dsp latency=3
        q += product >> 16;
    }
    quadratic = q;
}
