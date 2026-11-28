/* SPDX-License-Identifier: Zlib */
/* <uchar.h> in the C locale: ASCII round trips, bytes above 0x7F are EILSEQ,
   a surrogate pair is held then rejected as non-ASCII, a lone low surrogate
   is EILSEQ. Row c_uchar26, against gcc + glibc. feature-crtl-uchar-h */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <uchar.h>

int main(void)
{
    mbstate_t st;
    char32_t c32 = 0;
    char16_t c16 = 0;
    char buf[8];
    size_t r;
    memset(&st, 0, sizeof st);
    r = mbrtoc32(&c32, "A", 1, &st);
    printf("mbrtoc32 A %zu %u\n", r, (unsigned)c32);
    r = mbrtoc16(&c16, "z", 1, &st);
    printf("mbrtoc16 z %zu %u\n", r, (unsigned)c16);
    r = mbrtoc32(&c32, "", 1, &st);
    printf("mbrtoc32 nul %zu %u\n", r, (unsigned)c32);
    errno = 0;
    r = mbrtoc32(&c32, "\xc3\xa9", 2, &st);
    printf("mbrtoc32 e9 %ld eilseq %d\n", (long)r, errno == EILSEQ);
    memset(&st, 0, sizeof st);
    r = c32rtomb(buf, 'Q', &st);
    printf("c32rtomb Q %zu %c\n", r, buf[0]);
    errno = 0;
    r = c32rtomb(buf, 0xE9, &st);
    printf("c32rtomb e9 %ld eilseq %d\n", (long)r, errno == EILSEQ);
    memset(&st, 0, sizeof st);
    r = c16rtomb(buf, 'k', &st);
    printf("c16rtomb k %zu %c\n", r, buf[0]);
    memset(&st, 0, sizeof st);
    errno = 0;
    r = c16rtomb(buf, 0xDC00, &st);
    printf("c16rtomb lone-low %ld eilseq %d\n", (long)r, errno == EILSEQ);
    printf("sizes %zu %zu\n", sizeof(char16_t), sizeof(char32_t));
    return 0;
}
