/* The bit builtins in a --freestanding object (Gibux fs/event.c's
   __builtin_ctzll): cparser renames them to crtl's __pxx_builtin_* helpers,
   which a freestanding object can neither declare (no stdlib.h) nor link
   (no crtl). The unit now carries a static copy of each one it mentions.
   Driven by c_freestanding_bit_builtins_main.c, built by gcc, which compares
   every answer against gcc's own builtins. */
long long fs_bits(unsigned long long x, int which)
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
