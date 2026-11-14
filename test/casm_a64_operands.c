/* GNU C inline asm on aarch64 (compiler/casm_a64.inc): operands.
 *
 * The helpers are dropbear's sntrup761.c constant-time shapes, verbatim
 * templates. Each one is checked against the portable C expression it
 * replaces over a sweep of inputs (edges included), and the program prints
 * one line per helper. Every constraint form the file uses appears here:
 * "=r", "+r", "+&r", "=&r", a tied input, 16-, 32- and 64-bit operands,
 * %w on narrower types, a three-output block, plus a named operand and an
 * "i" immediate.
 *
 * Compiled with --target=aarch64 and run under qemu-aarch64; the same file
 * built for x86-64 takes the #else arms and must print the same.
 */
#include <stdio.h>
#include <stdint.h>

typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

#if defined(__aarch64__)
#define ASM 1
#else
#define ASM 0
#endif

static i16 negmask16(i16 x) {
#if ASM
  i16 y;
  __asm__ ("sbfx %w0,%w1,15,1" : "=r"(y) : "r"(x) : );
  return y;
#else
  return x < 0 ? -1 : 0;
#endif
}

static i64 negmask64(i64 x) {
#if ASM
  i64 y;
  __asm__ ("asr %0,%1,63" : "=r"(y) : "r"(x) : );
  return y;
#else
  return x < 0 ? -1 : 0;
#endif
}

static i32 shr32(i32 x, i32 s) {
#if ASM
  __asm__ ("asr %w0,%w0,%w1" : "+r"(x) : "r"(s) : );
  return x;
#else
  return x >> (s & 31);
#endif
}

static i16 shr16(i16 x, i16 s) {
#if ASM
  __asm__ ("and %w0,%w0,15\n sxth %w1,%w1\n asr %w1,%w1,%w0" : "+&r"(s), "+r"(x) : : );
  return x;
#else
  return (i16)(x >> (s & 15));
#endif
}

static i16 nonzero16(i16 x) {
#if ASM
  i16 z;
  __asm__ ("tst %w1,65535\n csetm %w0,ne" : "=r"(z) : "r"(x) : "cc");
  return z;
#else
  return x ? -1 : 0;
#endif
}

static i16 smaller16(i16 x, i16 y) {
#if ASM
  i16 z;
  __asm__ ("sxth %w0,%w1\n cmp %w0,%w2,sxth\n csetm %w0,lt" : "=&r"(z) : "r"(x), "r"(y) : "cc");
  return z;
#else
  return x < y ? -1 : 0;
#endif
}

static i16 equal16(i16 x, i16 y) {
#if ASM
  i16 z;
  __asm__ ("and %w0,%w1,65535\n cmp %w0,%w2,uxth\n cset %w0,eq" : "=&r"(z) : "r"(x), "r"(y) : "cc");
  return z;
#else
  return x == y;
#endif
}

static void minmax16(i16 *p, i16 *q) {
  i16 x = *p, y = *q;
#if ASM
  i16 r, s;
  __asm__ ("sxth %w0,%w0\n cmp %w0,%w3,sxth\n csel %w1,%w0,%w3,lt\n csel %w2,%w3,%w0,lt"
           : "+&r"(x), "=&r"(r), "=r"(s) : "r"(y) : "cc");
  *p = r; *q = s;
#else
  *p = x < y ? x : y; *q = x < y ? y : x;
#endif
}

static i64 min64(i64 x, i64 y) {
#if ASM
  __asm__ ("cmp %0,%1\n csel %0,%0,%1,lt" : "+r"(x) : "r"(y) : "cc");
  return x;
#else
  return x < y ? x : y;
#endif
}

static i32 ctz32(i32 x) {
#if ASM
  i32 y;
  __asm__ ("rbit %w0,%w1\n clz %w0,%w0" : "=r"(y) : "r"(x) : );
  return y;
#else
  i32 n = 0; uint32_t u = (uint32_t)x;
  if (!u) return 32;
  while (!(u & 1)) { u >>= 1; n++; }
  return n;
#endif
}

static i16 ctz16(i16 x) {
#if ASM
  i16 y;
  __asm__ ("orr %w0,%w1,-65536\n rbit %w0,%w0\n clz %w0,%w0" : "=r"(y) : "r"(x) : );
  return y;
#else
  i16 n = 0; uint16_t u = (uint16_t)x;
  if (!u) return 16;
  while (!(u & 1)) { u >>= 1; n++; }
  return n;
#endif
}

static i64 bottombit64(i64 x) {
#if ASM
  i64 y;
  __asm__ ("ubfx %0,%1,0,1" : "=r"(y) : "r"(x) : );
  return y;
#else
  return x & 1;
#endif
}

/* a named operand and an "i" immediate: x + 7, then << 2 */
static i32 named_imm(i32 x) {
#if ASM
  i32 y;
  __asm__ ("add %w[out],%w[in],%[k]\n lsl %w[out],%w[out],2" : [out] "=&r"(y) : [in] "r"(x), [k] "i"(7));
  return y;
#else
  return (i32)((uint32_t)(x + 7) << 2);
#endif
}

static const i64 v64[] = { 0, 1, -1, 2, -2, 7, 0x7fff, -0x8000, 0x10000, 0x7fffffff,
                           -0x7fffffff - 1, 0x123456789abcLL, -0x123456789abcLL,
                           INT64_MAX, INT64_MIN, 0x5555, -0x2222, 3000, -3000, 12345678 };
#define NV ((int)(sizeof v64 / sizeof v64[0]))

int main(void) {
  int i, j, bad;
  long sum;

  bad = 0; sum = 0;
  for (i = 0; i < NV; i++) {
    i16 a = (i16)v64[i];
    sum += negmask16(a) + nonzero16(a) + ctz16(a);
    if (negmask16(a) != (a < 0 ? -1 : 0)) bad++;
    if (nonzero16(a) != (a ? -1 : 0)) bad++;
  }
  printf("16 unary bad=%d sum=%ld\n", bad, sum);

  bad = 0; sum = 0;
  for (i = 0; i < NV; i++) {
    i64 a = v64[i];
    sum += negmask64(a) + bottombit64(a) + ctz32((i32)a) + named_imm((i32)a);
    if (negmask64(a) != (a < 0 ? -1 : 0)) bad++;
    if (bottombit64(a) != (a & 1)) bad++;
  }
  printf("64 unary bad=%d sum=%ld\n", bad, sum);

  bad = 0; sum = 0;
  for (i = 0; i < NV; i++)
    for (j = 0; j < NV; j++) {
      i16 a = (i16)v64[i], b = (i16)v64[j], p = a, q = b;
      sum += smaller16(a, b) + equal16(a, b) + shr16(a, b) + shr32((i32)v64[i], (i32)(v64[j] & 31));
      if (smaller16(a, b) != (a < b ? -1 : 0)) bad++;
      if (equal16(a, b) != (a == b)) bad++;
      minmax16(&p, &q);
      if (p != (a < b ? a : b) || q != (a < b ? b : a)) bad++;
      if (min64(v64[i], v64[j]) != (v64[i] < v64[j] ? v64[i] : v64[j])) bad++;
    }
  printf("binary bad=%d sum=%ld\n", bad, sum);
  return 0;
}
