/* A C program that includes a system library's header links that library.
 *
 * Every prototype in a C program defaulted to libc.so.6, so this built `ok`
 * with only libc in DT_NEEDED and died at start: "undefined symbol:
 * zlibVersion". A prototype now binds to the library its header names when
 * this machine's copy exports the symbol (the .dynsym check), so the binary
 * records libz.so.1. The make row asserts that DT_NEEDED entry as well as the
 * output, and skips on a machine without zlib's header.
 *
 * A compress/uncompress round trip and a crc32, so a wrong binding or a wrong
 * argument convention changes the printed values, not just whether it starts. */
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void)
{
    const char *msg = "hello hello hello hello hello zlib from pxx";
    unsigned char comp[256], back[256];
    uLongf clen = sizeof comp, blen = sizeof back;
    int rc = compress(comp, &clen, (const Bytef *)msg, strlen(msg));
    int rc2 = uncompress(back, &blen, comp, clen);
    back[blen] = 0;
    printf("%d %d %lu %s %lx\n", rc, rc2, (unsigned long)blen, (char *)back,
           (unsigned long)crc32(0L, (const Bytef *)msg, strlen(msg)));
    return 0;
}
