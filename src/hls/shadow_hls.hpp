#pragma once
#include <ap_int.h>
constexpr int SHADOW_DIM = 24;
// Raw signed Q16.16 words; products are arithmetically shifted by 16
// before accumulation. Matrix rows have a fixed stride of 24 words.
void shadow_hls(const ap_int<32> matrix[576], const ap_int<32> vector[24],
                ap_uint<5> dim, ap_int<32> direction[24],
                ap_int<64>& quadratic, ap_uint<1>& saturated,
                ap_uint<1>& error);
