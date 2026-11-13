/* File-scope initialisers are folded by the C constant folder (cparser's
   CEvalConst*), not by the code generator, so they need C's integer types:
   signed `>>` is arithmetic, unsigned is logical, `~0u` is 32 bits, and
   comparisons follow the usual arithmetic conversions. Every value below is
   also printed by the same file built with gcc; the two outputs must match.
   bug-c-a-file-scope-constant-right-shift-of-a-negative-value-is-logical */
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

static long g_shr_neg = -17 >> 2;          /* -5, was 4611686018427387899 */
static long g_shr_negl = -17L >> 2;        /* -5 */
static int g_shr_int = -17 >> 2;           /* -5 */
static unsigned long g_not_u = ~0u;        /* 4294967295, was -1 */
static unsigned long g_not_ul = ~0ul >> 4;
static unsigned long g_not_u_shr = ~0u >> 4;   /* 268435455 */
static long g_shl31 = 1 << 31;             /* INT_MIN on gcc */
static unsigned long g_shl31u = 1u << 31;
static long g_lt_mixed = -1 < 0u;          /* 0: -1 converts to UINT_MAX */
static long g_lt_long = -1L < 0u;          /* 1: long holds every unsigned */
static long g_eq_mixed = -1 == 0xFFFFFFFF; /* 1 */
static long g_div_u = -8u / 2;             /* 2147483644 */
static long g_div_s = -8 / 2;
static unsigned long g_div_ul = -8ul / 2;
static long g_mod_s = -7 % 3;
static long g_cast_uc = (unsigned char)300;     /* 44 */
static long g_cast_sc = (signed char)200;       /* -56 */
static long g_cast_s16 = (int16_t)0x18000;      /* -32768 */
static long g_cast_u32 = (uint32_t)-1;          /* 4294967295 */
static long g_cast_i32 = (int32_t)0xFFFFFFFF;   /* -1 */
static unsigned long g_cast_sz = (size_t)-1;
static long g_cast_bool = (_Bool)256;           /* 1 */
static long g_cast_shr = (int)0x80000000u >> 4; /* -134217728 */
static long g_tern = 1 ? -1 : 0u;               /* 4294967295 */
static long g_hex = 0x80000000 >> 1;            /* unsigned int: 1073741824 */
static long g_dec = 2147483648 >> 1;            /* long: 1073741824 */
static long g_neg_hex = -0x80000000;            /* unsigned: 2147483648 */
static long g_and = -1 & 0xFFFFu;
static long g_xor = -1 ^ 0u;
static long g_ul_mix = 5u - 10;                 /* 4294967291 */
static long long g_ll = -1LL >> 63;
static unsigned long long g_ull = ~0ULL >> 63;
static long g_sizeof = -1 < sizeof(int);        /* 0: size_t is unsigned */
enum { E_NEG = -17 >> 2, E_BIG = 1u << 31 >> 31 };
static long g_enum = E_NEG;
static char g_arr[(-17 >> 2) + 6];              /* dimension 1 */

int main(void)
{
    printf("shr %ld %ld %d\n", g_shr_neg, g_shr_negl, g_shr_int);
    printf("not %lu %lu %lu\n", g_not_u, g_not_ul, g_not_u_shr);
    printf("shl %ld %lu\n", g_shl31, g_shl31u);
    printf("cmp %ld %ld %ld %ld\n", g_lt_mixed, g_lt_long, g_eq_mixed, g_sizeof);
    printf("div %ld %ld %lu %ld\n", g_div_u, g_div_s, g_div_ul, g_mod_s);
    printf("cast %ld %ld %ld %ld %ld %lu %ld %ld\n", g_cast_uc, g_cast_sc, g_cast_s16,
           g_cast_u32, g_cast_i32, g_cast_sz, g_cast_bool, g_cast_shr);
    printf("misc %ld %ld %ld %ld %ld %ld %ld\n", g_tern, g_hex, g_dec, g_neg_hex, g_and,
           g_xor, g_ul_mix);
    printf("ll %lld %llu enum %ld %d arr %zu\n", g_ll, g_ull, g_enum, (int)E_BIG,
           sizeof g_arr);
    return 0;
}
