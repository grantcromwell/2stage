#include "shadow_hls.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <random>


static int64_t scale(int64_t p) {
    return p >= 0 ? p / 65536 : -((-p + 65535) / 65536);
}
int main() {
    std::mt19937 random(0x53484144);
    std::ofstream vectors("shadow_vectors.txt");
    int cases = 0;
    for (int test = 0; test < 80; ++test) {
        int dim = test < 32 ? test : 1 + random() % 24;
        ap_int<32> a[576], x[24], y[24];
        int32_t expected[24] = {};
        for (int i = 0; i < 576; ++i) {
            int32_t raw = static_cast<int32_t>(random());
            a[i] = test % 4 == 0 ? (i/24 == i%24 ? 65536 : 0) :
                   test % 4 == 1 ? raw : test % 4 == 2 ? raw / 4096 : 0;
        }
        for (int i = 0; i < 24; ++i) x[i] = test % 4 == 1 ?
            (i % 2 ? INT32_MIN : INT32_MAX) : static_cast<int32_t>(random()) / 4096;
        bool expected_sat = false, expected_error = dim == 0 || dim > 24;
        int64_t expected_q = 0;
        if (!expected_error) {
            for (int r = 0; r < dim; ++r) {
                int64_t sum = 0;
                for (int c = 0; c < dim; ++c)
                    sum += scale(int64_t(a[r*24+c].to_int()) * x[c].to_int());
                if (sum > INT32_MAX) { sum = INT32_MAX; expected_sat = true; }
                if (sum < INT32_MIN) { sum = INT32_MIN; expected_sat = true; }
                expected[r] = int32_t(sum);
            }
            for (int i = 0; i < dim; ++i)
                expected_q += scale(int64_t(x[i].to_int()) * expected[i]);
        }
        ap_int<64> q; ap_uint<1> sat, error;
        shadow_hls(a, x, dim, y, q, sat, error);
        if (q.to_int64() != expected_q || bool(sat) != expected_sat || bool(error) != expected_error) {
            std::fprintf(stderr, "FAIL scalar case %d dim %d\n", test, dim); return 1;
        }
        for (int i = 0; i < 24; ++i) if (y[i].to_int() != expected[i]) {
            std::fprintf(stderr, "FAIL direction case %d row %d\n", test, i); return 1;
        }
        vectors << std::hex << dim << ' ' << expected_sat << ' ' << expected_error << ' ' << uint64_t(expected_q) << '\n';
        for (auto v : a) vectors << std::hex << uint32_t(v.to_int()) << ' ';
        vectors << '\n';
        for (auto v : x) vectors << std::hex << uint32_t(v.to_int()) << ' ';
        vectors << '\n';
        for (auto v : expected) vectors << std::hex << uint32_t(v) << ' ';
        vectors << '\n';
        ++cases;
    }
    std::printf("PASS: %d HLS cases; dimensions 0..31, identity, zero, signed fractional and saturation inputs\n", cases);
}
