#pragma once
#include <array>
#include <cstdio>
#include <cstdint>
#include <map>
#include <string>
#include <type_traits>
#include <utility>

// Read existing model state only: enabling profiling does not change RTL or
// serialized checkpoint layout. Counter indices follow sst1_perf_counters.sv.
template<class T, class = void> struct ZsstProfile {
    bool open(const char*) { return false; }
    void sample(T*, uint64_t, uint32_t, uint32_t) {}
};

template<class T> struct ZsstProfile<T, std::void_t<decltype(
    std::declval<T>().__PVT__zsst_sim_device__DOT__performance_counters__DOT__live)>> {
    FILE* file=nullptr;
    std::string path;
    uint64_t cycles=0, instructions=0, swaps=0, fbi_active=0, host_blocked=0;
    std::array<uint64_t,32> states{};
    std::map<uint32_t,std::array<uint64_t,2>> pcs;
    bool open(const char* name) {
        path=name; file=fopen(name,"w");
        if (!file) return false;
        fprintf(file,"sim_time,cycles,instructions,swaps,fbi_active,host_blocked,host_reads,host_writes");
        for (int i=0;i<80;i++) fprintf(file,",p%d",i);
        for (int i=0;i<32;i++) fprintf(file,",fbi_state%d",i);
        fprintf(file,"\n"); return true;
    }
    void sample(T* core,uint64_t tick,uint32_t pc,uint32_t host_reads) {
        if (!file) return;
        ++cycles;
        instructions += core->system_i->__PVT__z486_cpu__DOT__i_first;
        swaps += core->__PVT__zsst_sim_device__DOT__swap_event;
        const bool active=!core->__PVT__zsst_sim_device__DOT__fbi_idle;
        fbi_active += active;
        host_blocked += core->__PVT__zsst_sim_device__DOT__frontend_core__DOT__frontend__DOT__host_req_valid &&
                        !core->__PVT__zsst_host_req_ready;
        ++states[core->__PVT__zsst_sim_device__DOT__fbi__DOT__state];
        if (!(cycles%64)) ++pcs[pc][active];
        if (cycles==1 || !(cycles%1000000)) {
            fprintf(file,"%llu,%llu,%llu,%llu,%llu,%llu,%u,%u",
                (unsigned long long)tick,(unsigned long long)cycles,
                (unsigned long long)instructions,(unsigned long long)swaps,
                (unsigned long long)fbi_active,(unsigned long long)host_blocked,
                host_reads,core->dbg_zsst_host_writes);
            for (int i=0;i<80;i++) fprintf(file,",%llu",(unsigned long long)
                core->__PVT__zsst_sim_device__DOT__performance_counters__DOT__live[i]);
            for (auto count:states) fprintf(file,",%llu",(unsigned long long)count);
            fprintf(file,"\n"); fflush(file);
        }
    }
    ~ZsstProfile() {
        if (!file) return;
        fclose(file);
        FILE* out=fopen((path+".pc.csv").c_str(),"w");
        if (!out) return;
        fprintf(out,"linear_pc,fbi_idle_samples,fbi_active_samples\n");
        for (auto& item:pcs) fprintf(out,"%08x,%llu,%llu\n",item.first,
            (unsigned long long)item.second[0],(unsigned long long)item.second[1]);
        fclose(out);
    }
};
