

#define main shadow_daemon_main
#include "shadow_usb_daemon.c"
#undef main
#include <assert.h>
#include <sys/socket.h>

static void resident_tests(uint32_t *regs)
{
    int fds[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    uint8_t m[2312] = {0}, b[200] = {0}, reply[272];
    put32(m, 24);
    put32(m + 4, 123);
    put32(m + 2308, crc32(m, 2308));
    assert(write_exact(fds[0], m, sizeof(m)) == 0);
    assert(resident_command(fds[1], 'M') == 0);
    assert(read_exact(fds[0], reply, 136) == 0);
    assert(le32(reply + 4) == 0 && resident_dim == 24);
    assert(regs[0x100 / 4] == 123);
    put32(b, 2);
    put32(b + 4, 321);
    put32(b + 100, 456);
    put32(b + 196, crc32(b, 196));
    assert(write_exact(fds[0], b, sizeof(b)) == 0);
    assert(resident_command(fds[1], 'B') == 0);
    assert(read_exact(fds[0], reply, sizeof(reply)) == 0);
    for (unsigned i = 0; i < 2; ++i) {
        assert(le32(reply + i * 136 + 4) == 4);
        assert(le32(reply + i * 136 + 132) == crc32(reply + i * 136, 132));
    }
    assert(regs[0x100 / 4] == 123 && regs[0xa00 / 4] == 456);
    b[4] ^= 1;
    assert(write_exact(fds[0], b, sizeof(b)) == 0);
    assert(resident_command(fds[1], 'B') == 0);
    assert(read_exact(fds[0], reply, sizeof(reply)) == 0);
    assert(le32(reply + 4) == 0x40000000u);
    assert(regs[0xa00 / 4] == 456);
    m[4] ^= 1;
    assert(write_exact(fds[0], m, sizeof(m)) == 0);
    assert(resident_command(fds[1], 'M') == 0);
    assert(read_exact(fds[0], reply, 136) == 0);
    assert(le32(reply + 4) == 0x40000000u && resident_dim == 0);
    b[4] ^= 1;
    assert(write_exact(fds[0], b, sizeof(b)) == 0);
    assert(resident_command(fds[1], 'B') == 0);
    assert(read_exact(fds[0], reply, sizeof(reply)) == 0);
    assert(le32(reply + 4) == 0x20000000u);
    put32(m, 25);
    put32(m + 2308, crc32(m, 2308));
    assert(write_exact(fds[0], m, sizeof(m)) == 0);
    assert(resident_command(fds[1], 'M') == 0);
    assert(read_exact(fds[0], reply, 136) == 0);
    assert(le32(reply + 4) == 0x20000000u && resident_dim == 0);
    put32(b, 65);
    assert(write_exact(fds[0], b, 4) == 0);
    assert(resident_command(fds[1], 'B') == -1);
    close(fds[0]); close(fds[1]);
}

int main(void)
{
    init_crc_table();
    assert(crc32((const uint8_t *)"123456789", 9) == 0xcbf43926u);
    uint8_t crc_data[6152];
    for (unsigned i = 0; i < sizeof(crc_data); ++i) crc_data[i] = (uint8_t)(i * 29u + 7u);
    for (unsigned n = 0; n < sizeof(crc_data); n += 31) {
        uint32_t slow = ~0u;
        for (unsigned i = 0; i < n; ++i) {
            slow ^= crc_data[i];
            for (unsigned bit = 0; bit < 8; ++bit)
                slow = (slow >> 1) ^ (0xedb88320u & (0u - (slow & 1u)));
        }
        assert(crc32(crc_data, n) == ~slow);
    }
    uint8_t bytes[4];
    put32(bytes, 0x12345678u);
    assert(le32(bytes) == 0x12345678u);

    uint32_t regs[AXI_BYTES / 4] = {0};
    axi = regs;
    regs[4 / 4] = 4; 
    regs[0x58 / 4] = 3149;
    regs[0xa80 / 4] = 0xdeadbeefu;
    regs[0xb00 / 4] = 0x11223344u;
    regs[0xb04 / 4] = 0x55667788u;

    uint8_t request[INPUT_WORDS * 4 + 4] = {0};
    uint32_t response[RESPONSE_WORDS] = {0};
    put32(request, 24);
    put32(request + 4 * (1 + 575), 0x12345678u);
    put32(request + 4 * (577 + 23), 0x87654321u);
    put32(request + INPUT_WORDS * 4, crc32(request, INPUT_WORDS * 4));
    score(request, response);
    assert(response[0] == 0x31444853u);
    assert(response[1] & 4u);
    assert(response[2] == 3149);
    assert(response[7] == 0xdeadbeefu);
    assert(response[31] == 0x11223344u && response[32] == 0x55667788u);
    assert(regs[(0x100 + 4 * 575) / 4] == 0x12345678u);
    assert(regs[(0xa00 + 4 * 23) / 4] == 0x87654321u);
    assert(regs[0] == 0); 

    request[4] ^= 1;
    memset(response, 0, sizeof(response));
    score(request, response);
    assert(response[1] == 0x40000000u);
    resident_tests(regs);
    puts("PASS: CRC, framing, AXI boundaries, result packing, resident matrix, batches, missing matrix and invalid count");
    return 0;
}
