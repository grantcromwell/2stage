#include "fixed_point_matrix.h"
#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <vector>
using namespace cromwell::synth;
struct Case { unsigned n, sat, err; uint64_t q; std::vector<int32_t> x,y; std::vector<std::vector<int32_t>> a; };
volatile uint64_t sink = 0;
int main(int argc, char** argv) {
    if(argc != 2) return 2;
    std::ifstream in(argv[1]); in >> std::hex;
    std::vector<Case> cases;
    for(int k=0;k<80;++k) {
        Case c; in >> c.n >> c.sat >> c.err >> c.q;
        uint32_t a[576],x[24],y[24];
        for(auto& v:a) in >> v;
        for(auto& v:x) in >> v;
        for(auto& v:y) in >> v;
        if(!in) throw std::runtime_error("vector parse failure");
        if(c.n<=24) {
            c.x.assign(x,x+c.n); c.y.assign(y,y+c.n);
            for(unsigned r=0;r<c.n;++r) c.a.emplace_back(a+24*r,a+24*r+c.n);
        } else { c.x.resize(c.n); c.a.resize(c.n); }
        bool rejected=false;
        try {
            auto o=score_q16_16(c.x,c.a);
            if(c.err || o.direction_raw!=c.y || uint64_t(o.squared_distance_raw)!=c.q || o.saturated!=bool(c.sat))
                throw std::runtime_error("CPU oracle mismatch");
        } catch(const std::invalid_argument&) { rejected=true; }
        if(rejected!=bool(c.err)) throw std::runtime_error("invalid dimension mismatch");
        cases.push_back(c);
    }
    const auto& c=cases.at(24);
    if(c.n!=24) return 3;
    for(int i=0;i<10000;++i) sink=uint64_t(score_q16_16(c.x,c.a).squared_distance_raw);
    std::vector<double> ns;
    for(int i=0;i<10000;++i) {
        auto start=std::chrono::steady_clock::now();
        auto o=score_q16_16(c.x,c.a);
        auto end=std::chrono::steady_clock::now();
        sink=uint64_t(o.squared_distance_raw);
        ns.push_back(std::chrono::duration<double,std::nano>(end-start).count());
    }
    std::cout << "{\"baseline\":\"existing C++ host score_q16_16; prequantized cached inputs; output allocation included; no USB or serialization\",\"compiler\":\"" << __VERSION__ << "\",\"flags\":\"-O3 -std=c++14 -march=native; no LTO\",\"parity_cases\":80,\"invalid_dimension_behavior\":\"CPU exception vs FPGA error flag\",\"dimension\":24,\"warmups\":10000,\"samples\":10000,\"raw_ns\":[";
    for(size_t i=0;i<ns.size();++i) std::cout << (i?",":"") << ns[i];
    std::sort(ns.begin(),ns.end());
    std::cout << "],\"mean_ns\":" << std::accumulate(ns.begin(),ns.end(),0.0)/ns.size()
              << ",\"p50_ns\":" << (ns[4999]+ns[5000])/2 << ",\"p95_ns\":" << ns[9499]
              << ",\"p99_ns\":" << ns[9899] << ",\"min_ns\":" << ns.front() << ",\"max_ns\":" << ns.back() << "}\n";
}
