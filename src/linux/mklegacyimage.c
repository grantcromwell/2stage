
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

struct image_header {
    uint32_t magic, hcrc, time, size, load, ep, dcrc;
    uint8_t os, arch, type, comp;
    char name[32];
};

enum { IH_MAGIC = 0x27051956, IH_OS_LINUX = 5, IH_ARCH_ARM = 2,
       IH_TYPE_KERNEL = 2, IH_TYPE_RAMDISK = 3, IH_COMP_NONE = 0,
       IH_COMP_GZIP = 1 };

static void fail(const char *what) { perror(what); exit(1); }

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr, "usage: %s kernel|ramdisk load entry input output name\\n", argv[0]);
        return 2;
    }
    int ramdisk = !strcmp(argv[1], "ramdisk");
    if (!ramdisk && strcmp(argv[1], "kernel")) return 2;
    char *end;
    uint32_t load = strtoul(argv[2], &end, 0); if (*end) return 2;
    uint32_t entry = strtoul(argv[3], &end, 0); if (*end) return 2;
    FILE *in = fopen(argv[4], "rb"); if (!in) fail(argv[4]);
    if (fseek(in, 0, SEEK_END)) fail("seek");
    long n = ftell(in); if (n < 0 || (uint64_t)n > UINT32_MAX) fail("size");
    rewind(in);
    unsigned char *data = malloc((size_t)n ? (size_t)n : 1); if (!data) fail("malloc");
    if (fread(data, 1, (size_t)n, in) != (size_t)n) fail("read");
    fclose(in);
    struct image_header h = {0};
    h.magic = htonl(IH_MAGIC); h.size = htonl((uint32_t)n);
    h.load = htonl(load); h.ep = htonl(entry); h.dcrc = htonl(crc32(0, data, (uInt)n));
    h.os = IH_OS_LINUX; h.arch = IH_ARCH_ARM;
    h.type = ramdisk ? IH_TYPE_RAMDISK : IH_TYPE_KERNEL;
    h.comp = ramdisk ? IH_COMP_GZIP : IH_COMP_NONE;
    snprintf(h.name, sizeof h.name, "%s", argv[7]);
    h.hcrc = 0; h.hcrc = htonl(crc32(0, (const Bytef *)&h, sizeof h));
    FILE *out = fopen(argv[6], "wb"); if (!out) fail(argv[6]);
    if (fwrite(&h, 1, sizeof h, out) != sizeof h || fwrite(data, 1, (size_t)n, out) != (size_t)n) fail("write");
    if (fclose(out)) fail("close");
    free(data);
    return 0;
}
