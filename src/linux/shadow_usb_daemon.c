

#define _DEFAULT_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

enum { AXI_BASE = 0x43c00000, AXI_BYTES = 4096, INPUT_WORDS = 601,
       RESPONSE_WORDS = 34, FCLK_HZ = 100000000 };
static volatile uint32_t *axi;
static unsigned resident_dim;
static uint32_t crc_table[256];

static void init_crc_table(void)
{
    for (unsigned i = 0; i < 256; ++i) {
        uint32_t c = i;
        for (unsigned b = 0; b < 8; ++b)
            c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
        crc_table[i] = c;
    }
}

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void put32(uint8_t *p, uint32_t v)
{
    for (unsigned i = 0; i != 4; ++i) p[i] = (uint8_t)(v >> (8 * i));
}

static uint32_t crc32(const uint8_t *p, size_t n)
{
    uint32_t c = ~0u;
    for (size_t i = 0; i < n; ++i)
        c = crc_table[(c ^ p[i]) & 0xffu] ^ (c >> 8);
    return ~c;
}

static uint64_t now_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) { perror("clock_gettime"); exit(1); }
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint32_t elapsed32(uint64_t start)
{
    uint64_t delta = now_ns() - start;
    return delta > UINT32_MAX ? UINT32_MAX : (uint32_t)delta;
}

static int read_exact(int fd, uint8_t *p, size_t n)
{
    while (n) {
        ssize_t got = read(fd, p, n);
        if (got > 0) { p += got; n -= (size_t)got; continue; }
        if (got < 0 && errno == EINTR) continue;
        if (got < 0 && errno == EAGAIN) { usleep(1000); continue; }
        return -1;
    }
    return 0;
}

static int write_exact(int fd, const uint8_t *p, size_t n)
{
    while (n) {
        ssize_t sent = write(fd, p, n);
        if (sent > 0) { p += sent; n -= (size_t)sent; continue; }
        if (sent < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        return -1;
    }
    return 0;
}

static inline void wr(unsigned offset, uint32_t value)
{
    axi[offset / 4] = value;
    __sync_synchronize();
}

static inline uint32_t rd(unsigned offset)
{
    uint32_t value = axi[offset / 4];
    __sync_synchronize();
    return value;
}

static void compute(const uint8_t *vector, uint32_t response[RESPONSE_WORDS],
                    uint64_t total_start, unsigned dim)
{
    response[0] = 0x31444853u; 
    response[6] = 1000000000u; 
    for (unsigned i = 0; i < dim && i < 24; ++i)
        wr(0xa00 + i * 4, le32(vector + 4 * i));

    uint64_t compute_start = now_ns();
    wr(0, 5); 
    uint32_t status;
    do {
        status = rd(4);
        if (now_ns() - compute_start > 100000000ull) {
            response[1] = status | 0x80000000u;
            wr(0, 2); 
            resident_dim = 0;
            return;
        }
    } while (!(status & 4u));

    response[3] = elapsed32(compute_start);
    response[1] = status;
    response[2] = rd(0x58);
    for (unsigned i = 0; i < 24; ++i) response[7 + i] = rd(0xa80 + i * 4);
    response[31] = rd(0xb00);
    response[32] = rd(0xb04);
    wr(0, 0); 
    response[4] = elapsed32(total_start);
    response[5] = 0; 
}

static void score(const uint8_t *request, uint32_t response[RESPONSE_WORDS])
{
    uint64_t start = now_ns();
    response[0] = 0x31444853u;
    response[6] = 1000000000u;
    if (crc32(request, INPUT_WORDS * 4) != le32(request + INPUT_WORDS * 4)) {
        response[1] = 0x40000000u;
        return;
    }
    resident_dim = 0; 
    wr(0, 0);
    wr(8, le32(request));
    for (unsigned i = 0; i < 576; ++i)
        wr(0x100 + i * 4, le32(request + 4 * (1 + i)));
    compute(request + 4 * 577, response, start, le32(request));
}

static void pack_response(uint8_t *reply, const uint32_t *words)
{
    for (unsigned i = 0; i < RESPONSE_WORDS - 1; ++i)
        put32(reply + i * 4, words[i]);
    put32(reply + 132, crc32(reply, 132));
}





static int resident_command(int fd, uint8_t command)
{
    uint8_t request[4 + 64 * 96 + 4], reply[64 * 136];
    uint32_t words[RESPONSE_WORDS] = {0};
    if (read_exact(fd, request, 4)) return -1;
    unsigned count = command == 'M' ? 1 : le32(request);
    if (!count || count > 64) return -1;
    size_t size = command == 'M' ? 4 + 576 * 4 : 4 + count * 96;
    if (read_exact(fd, request + 4, size)) return -1;
    uint64_t start = now_ns();
    uint32_t failure = 0;
    if (crc32(request, size) != le32(request + size)) failure = 0x40000000u;
    if (command == 'M') {
        resident_dim = 0;
        unsigned dim = le32(request);
        if (!failure && (!dim || dim > 24)) failure = 0x20000000u;
        if (!failure) {
            wr(0, 0);
            wr(8, dim);
            for (unsigned i = 0; i < 576; ++i)
                wr(0x100 + 4 * i, le32(request + 4 + 4 * i));
            resident_dim = dim;
        }
    } else if (!resident_dim && !failure) failure = 0x20000000u;
    for (unsigned i = 0; i < count; ++i) {
        memset(words, 0, sizeof(words));
        words[0] = 0x31444853u;
        words[6] = 1000000000u;
        words[1] = failure;
        if (!failure && command == 'B') {
            if (!resident_dim) words[1] = 0x20000000u;
            else compute(request + 4 + i * 96, words, now_ns(), resident_dim);
        }
        if (command == 'M') words[4] = elapsed32(start);
        pack_response(reply + i * 136, words);
    }
    return write_exact(fd, reply, count * 136);
}

static void run_link(int fd)
{
    resident_dim = 0;
    uint8_t request[INPUT_WORDS * 4 + 4];
    uint8_t reply[RESPONSE_WORDS * 4];
    uint32_t words[RESPONSE_WORDS];
    for (;;) {
        uint8_t command;
        if (read_exact(fd, &command, 1) != 0) break;
        if (command == 'P') {
            put32(reply, 0x314e4542u); 
            put32(reply + 4, rd(0x5c));
            put32(reply + 8, 1000000000u);
            put32(reply + 12, FCLK_HZ);
            if (write_exact(fd, reply, 16) != 0) break;
        } else if (command == 'M' || command == 'B') {
            if (resident_command(fd, command)) break;
        } else if (command == 'S') {
            if (read_exact(fd, request, sizeof(request)) != 0) break;
            memset(words, 0, sizeof(words));
            score(request, words);
            pack_response(reply, words);
            if (write_exact(fd, reply, sizeof(reply)) != 0) break;
        } else {
            fprintf(stderr, "unsupported gadget command 0x%02x\n", command);
        }
    }
}

int main(int argc, char **argv)
{
    init_crc_table();
    const char *tty = argc > 1 ? argv[1] : "/dev/ttyGS0";
    int mem = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem < 0) { perror("/dev/mem"); return 1; }
    void *map = mmap(NULL, AXI_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, mem, AXI_BASE);
    if (map == MAP_FAILED) { perror("mmap accelerator"); return 1; }
    axi = map;
    if (rd(0x5c) != 0x53484431u) {
        fprintf(stderr, "SHD1 accelerator signature missing; program the matching PL bitstream\n");
        return 1;
    }
    for (;;) {
        int fd = open(tty, O_RDWR | O_NOCTTY);
        if (fd < 0) { perror(tty); sleep(1); continue; }
        struct termios term;
        if (tcgetattr(fd, &term) == 0) {
            cfmakeraw(&term);
            term.c_cflag |= CLOCAL | CREAD;
            if (tcsetattr(fd, TCSANOW, &term) != 0) perror("tcsetattr");
        }
        run_link(fd);
        close(fd);
        sleep(1);
    }
}
