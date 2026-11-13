/* gcc-built driver for c_freestanding_bit_builtins.c: the pxx object's
   answers against gcc's builtins, over a spread of values. Prints "bits ok N"
   or the first mismatch. */
#include <stdio.h>

long long fs_bits(unsigned long long x, int which);

static long long ref(unsigned long long x, int which)
{
    switch (which) {
    case 0:  return x ? __builtin_ctzll(x) : -1;
    case 1:  return x ? __builtin_clzll(x) : -1;
    case 2:  return __builtin_popcountll(x);
    case 3:  return __builtin_ffsll((long long)x);
    case 4:  return __builtin_parityll(x);
    case 5:  return (unsigned)x ? __builtin_ctz((unsigned)x) : -1;
    case 6:  return (unsigned)x ? __builtin_clz((unsigned)x) : -1;
    case 7:  return __builtin_popcount((unsigned)x);
    case 8:  return __builtin_ffs((int)x);
    case 9:  return __builtin_parity((unsigned)x);
    case 10: return x ? __builtin_ctzl(x) : -1;
    case 11: return __builtin_popcountl(x);
    case 12: return (long long)__builtin_bswap64(x);
    case 13: return __builtin_bswap32((unsigned)x);
    case 14: return __builtin_bswap16((unsigned short)x);
    }
    return -2;
}

int main(void)
{
    unsigned long long v[] = { 0, 1, 2, 3, 0x80, 0x8000000000000000ull, 0xffffffffffffffffull,
                               0x123456789abcdef0ull, 0x00f0000000000000ull, 0x80000000ull,
                               0xfffe, 0x10000, 0x7fffffff };
    int n = 0;
    for (unsigned i = 0; i < sizeof v / sizeof v[0]; i++)
        for (int w = 0; w <= 14; w++) {
            long long a = fs_bits(v[i], w), b = ref(v[i], w);
            if (a != b) {
                printf("bits MISMATCH x=%llx which=%d pxx=%lld gcc=%lld\n", v[i], w, a, b);
                return 1;
            }
            n++;
        }
    printf("bits ok %d\n", n);
    return 0;
}
