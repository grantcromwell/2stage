
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_ns(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) { perror("clock_gettime"); exit(1); }
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}
static int compare(const void *a, const void *b) {
    uint64_t x=*(const uint64_t*)a, y=*(const uint64_t*)b;
    return (x>y)-(x<y);
}
static void put(volatile uint32_t *r, unsigned offset, uint32_t value) {
    atomic_thread_fence(memory_order_seq_cst);
    r[offset/4]=value;
    atomic_thread_fence(memory_order_seq_cst);
}
static uint32_t get(volatile uint32_t *r, unsigned offset) {
    atomic_thread_fence(memory_order_seq_cst);
    uint32_t value=r[offset/4];
    atomic_thread_fence(memory_order_seq_cst);
    return value;
}
int main(int argc,char **argv) {
    if(argc!=2) { fprintf(stderr,"Usage: %s /dev/uioN\n",argv[0]); return 2; }
    int fd=open(argv[1],O_RDWR|O_CLOEXEC);
    if(fd<0) {perror("open UIO");return 1;}
    volatile uint32_t *r=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(r==MAP_FAILED) {perror("mmap");close(fd);return 1;}
    int failed=0;
    uint64_t samples[100], total=0, stream_start=0, stream_elapsed=0;
    uint32_t cycles=0;
    if(get(r,0x5c)!=0x53484431) {fprintf(stderr,"SHD1 signature missing\n");failed=1;goto out;}
    put(r,0,2);
    for(int test=0;test<110;test++) {
        if(test==10) stream_start=now_ns();
        uint64_t start=now_ns();
        put(r,0,0);
        put(r,8,24);
        for(int i=0;i<24;i++) for(int j=0;j<24;j++) put(r,0x100+4*(24*i+j),i==j?65536:0);
        for(int i=0;i<24;i++) put(r,0xa00+4*i,65536);
        put(r,0,5);
        struct pollfd p={.fd=fd,.events=POLLIN};
        int ret;
        do ret=poll(&p,1,1000); while(ret<0 && errno==EINTR);
        if(ret!=1 || !(p.revents&POLLIN)) {fprintf(stderr,"IRQ timeout/error\n");failed=1;goto out;}
        uint32_t events;
        if(read(fd,&events,4)!=4) {perror("UIO read");failed=1;goto out;}
        if((get(r,4)&0x1c)!=4) {fprintf(stderr,"unexpected status\n");failed=1;goto out;}
        for(int i=0;i<24;i++) if(get(r,0xa80+4*i)!=65536) {fprintf(stderr,"direction mismatch\n");failed=1;goto out;}
        uint64_t q=get(r,0xb00); q|=(uint64_t)get(r,0xb04)<<32;
        if(q!=24*65536) {fprintf(stderr,"quadratic mismatch\n");failed=1;goto out;}
        cycles=get(r,0x58);
        if(cycles!=725) {fprintf(stderr,"latency mismatch: %u\n",cycles);failed=1;goto out;}
        put(r,0,0);
        uint32_t enable_irq=1;
        if(write(fd,&enable_irq,sizeof(enable_irq))!=sizeof(enable_irq)) {perror("UIO IRQ re-enable");failed=1;goto out;}
        uint64_t elapsed=now_ns()-start;
        if(test>=10) {samples[test-10]=elapsed;total+=elapsed;}
    }
    stream_elapsed=now_ns()-stream_start;
    qsort(samples,100,sizeof(*samples),compare);
    printf("{\"dimension\":24,\"samples\":100,\"warmups\":10,\"compute_cycles\":%u,"
           "\"rtt_mean_ns\":%.2f,\"rtt_p50_ns\":%"PRIu64",\"rtt_p95_ns\":%"PRIu64","
           "\"sustained_updates_per_second\":%.2f}\n",cycles,total/100.0,samples[49],samples[94],1e11/stream_elapsed);
out:
    put(r,0,2);
    munmap((void*)r,4096);close(fd);return failed;
}
