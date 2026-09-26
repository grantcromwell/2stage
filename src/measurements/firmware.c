#include <stdint.h>
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define UART 0xe0001000u
#define ACC 0x43c00000u
#define TIMER 0xf8f00200u
#define GICC 0xf8f00100u
#define GICD 0xf8f01000u
#define TIMER_HZ 325000000u
#define PACKET_WORDS 601
static uint32_t input[PACKET_WORDS];
static uint32_t response[34];
static uint32_t records[1000][4];
static uint32_t expected[26];
static volatile uint32_t irq_seen, irq_count, irq_tick;
static inline void barrier(void) { __asm__ volatile("dsb sy" ::: "memory"); }
static uint32_t ticks(void) { barrier(); return REG(TIMER); }
static void wr(uint32_t off,uint32_t value) { REG(ACC+off)=value; }
static uint32_t rd(uint32_t off) { return REG(ACC+off); }
static uint8_t getbyte(void) { while(REG(UART+0x2c)&2) {} return REG(UART+0x30); }
static void putbyte(uint8_t b) { while(REG(UART+0x2c)&16) {} REG(UART+0x30)=b; }
static void tx_flush(void) { while(!(REG(UART+0x2c)&8) || (REG(UART+0x2c)&0x800)) {} }
static uint32_t getword(void) {
    uint32_t v=0; for(unsigned i=0;i<4;i++) v|=(uint32_t)getbyte()<<(8*i); return v;
}
static void putword(uint32_t v) { for(unsigned i=0;i<4;i++) putbyte(v>>(8*i)); }
static uint32_t crc_byte(uint32_t c,uint8_t v) {
    c^=v; for(unsigned i=0;i<8;i++) c=(c>>1)^(0xedb88320u & (0u-(c&1))); return c;
}
static uint32_t crc_words(const uint32_t *words,unsigned n) {
    uint32_t c=~0u;
    for(unsigned i=0;i<n;i++) for(unsigned j=0;j<4;j++) c=crc_byte(c,words[i]>>(j*8));
    return ~c;
}
static void uart_rate(uint32_t baud) {
    tx_flush();
    REG(UART)=0x28;
    REG(UART+0x04)=0x20;
    
    
    REG(UART+0x18)=baud==230400 ? 62 : 124;
    REG(UART+0x34)=6;
    REG(UART)=3;
    while(REG(UART)&3) {}
    REG(UART)=0x14;
}
void irq_handler(void) {
    uint32_t id=REG(GICC+0x0c);
    if((id&1023)==61) {
        irq_tick=REG(TIMER);
        wr(0,1); barrier(); 
        irq_count++; irq_seen=1;
    }
    if((id&1023)<1020) REG(GICC+0x10)=id;
    barrier();
}
static void init_irq(void) {
    REG(GICC)=0; REG(GICD)=0;
    REG(GICD+0x180+4)=1u<<29;
    REG(GICD+0x280+4)=1u<<29;
    *(volatile uint8_t *)(GICD+0x400+61)=0x80;
    *(volatile uint8_t *)(GICD+0x800+61)=1;
    REG(GICD+0xc0c)&=~(3u<<26);
    REG(GICD+0x104)=1u<<29;
    REG(GICC+4)=0xff; REG(GICC+8)=0;
    REG(GICD)=1; REG(GICC)=1;
    barrier(); __asm__ volatile("cpsie i" ::: "memory");
}
static void compute(void) {
    uint32_t all_start=ticks(), status=0;
    wr(0,0); wr(8,input[0]);
    for(unsigned i=0;i<576;i++) wr(0x100+4*i,input[1+i]);
    for(unsigned i=0;i<24;i++) wr(0xa00+4*i,input[577+i]);
    barrier(); irq_seen=0;
    uint32_t compute_start=ticks();
    wr(0,5); barrier();
    while(!irq_seen) {
        if((uint32_t)(ticks()-compute_start)>TIMER_HZ/100) {status=0x80000000u;break;}
    }
    uint32_t compute_elapsed=irq_seen ? irq_tick-compute_start : ticks()-compute_start;
    status|=rd(4);
    for(unsigned i=0;i<24;i++) response[7+i]=rd(0xa80+4*i);
    response[31]=rd(0xb00); response[32]=rd(0xb04);
    response[0]=0x31444853; response[1]=status; response[2]=rd(0x58);
    response[3]=compute_elapsed;
    wr(0,0); barrier();
    response[4]=ticks()-all_start;
    response[5]=irq_count; response[6]=TIMER_HZ;
}
int main(void) {
    REG(0x0002d000)=0x42454e31;
    REG(TIMER+8)=0; REG(TIMER)=0; REG(TIMER+4)=0; REG(TIMER+8)=1;
    REG(UART+0x0c)=0x1fff; REG(UART+0x14)=0x1fff;
    uart_rate(115200);
    wr(0,2); barrier(); init_irq();
    REG(0x0002d004)=rd(0x5c);
    for(;;) {
        uint8_t command=getbyte(); REG(0x0002d008)=command;
        if(command=='P') {
            putword(0x314e4542); putword(rd(0x5c)); putword(TIMER_HZ); putword(100000000);
        } else if(command=='V') {
            uint32_t baud=getword();
            uint32_t valid=baud==230400||baud==115200;
            putword(valid ? baud:0);
            if(valid) uart_rate(baud);
        } else if(command=='S') {
            for(unsigned i=0;i<PACKET_WORDS;i++) input[i]=getword();
            uint32_t checksum=getword();
            if(crc_words(input,PACKET_WORDS)!=checksum) {
                for(unsigned i=0;i<33;i++) response[i]=0;
                response[0]=0x31444853; response[1]=0x40000000u;
            } else {
                compute();
                for(unsigned i=0;i<26;i++) expected[i]=response[7+i];
            }
            response[33]=crc_words(response,33);
            for(unsigned i=0;i<34;i++) putword(response[i]);
        } else if(command=='B') {
            uint32_t count=getword(); if(count>1000) count=1000;
            uint32_t start=ticks(), errors=0, before=irq_count;
            for(unsigned i=0;i<count;i++) {
                compute();
                uint32_t bad=(response[1]&0x80000008u)!=0 || response[2]!=input[0]*input[0]+5*input[0]+29;
                for(unsigned j=0;j<26;j++) if(response[7+j]!=expected[j]) bad=1;
                errors+=bad;
                records[i][0]=response[4]; records[i][1]=response[3]; records[i][2]=response[2]; records[i][3]=bad;
            }
            uint32_t elapsed=ticks()-start;
            putword(0x31484342); putword(count); putword(TIMER_HZ); putword(elapsed); putword(errors); putword(irq_count-before);
            for(unsigned i=0;i<count;i++) for(unsigned j=0;j<4;j++) putword(records[i][j]);
            putword(crc_words(&records[0][0],count*4));
        } else if(command=='U') {
            uint32_t n=getword(), c=~0u, start=ticks();
            for(unsigned i=0;i<n;i++) c=crc_byte(c,getbyte());
            uint32_t elapsed=ticks()-start;
            putword(0x314c5055); putword(~c); putword(elapsed);
        } else if(command=='D') {
            uint32_t n=getword(), c=~0u;
            putword(0x314e5744);
            for(unsigned i=0;i<n;i++) {uint8_t b=i*29+7;putbyte(b);c=crc_byte(c,b);}
            putword(~c);
        }
    }
}
