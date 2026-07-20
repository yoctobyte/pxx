/* SPDX-License-Identifier: Zlib */
/* exp2 (feature-crtl-implement-libc-assumptions).

   <math.h> declared exp2 and nothing defined it, so a C program calling it
   compiled, linked, and then died at runtime with "undefined symbol: exp2".
   That is the declared-but-unimplemented class the collector ticket lists
   first, and it is the worst-behaved one: the failure lands at run time, in a
   program that looked fine.

   Expected values judged against 120-digit references (exp(x*ln2) in Decimal);
   all 16 are the correctly rounded double, 0 ulp. Bit patterns and no printf,
   for the same reason as crtl_trig_huge.c.

   Returns 42 on success, or 100+index of the first mismatch. */

#include "math.c"

typedef struct { double x; unsigned long long want; } tcase;

static const tcase cases[] = {
  { 0.0,         0x3ff0000000000000ULL },
  { 1.0,         0x4000000000000000ULL },
  { -1.0,        0x3fe0000000000000ULL },
  { 10.0,        0x4090000000000000ULL },
  { -10.0,       0x3f50000000000000ULL },
  { 0.5,         0x3ff6a09e667f3bcdULL },
  { -0.5,        0x3fe6a09e667f3bcdULL },
  { 3.7,         0x4029fdf8bcce533eULL },
  { -3.7,        0x3fb3b2c47bff8328ULL },
  { 52.0,        0x4330000000000000ULL },
  { 1023.0,      0x7fe0000000000000ULL },
  { -1022.0,     0x0010000000000000ULL },
  { 0.1,         0x3ff125fbee250664ULL },
  { 100.25,      0x463306fe0a31b715ULL },
  { -200.75,     0x336306fe0a31b715ULL },
  { 1e-8,        0x3ff0000001dc53beULL },
};

static unsigned long long bits(double d) {
  union { double d; unsigned long long u; } u; u.d = d; return u.u;
}

int main(void) {
  int i, n = (int)(sizeof(cases)/sizeof(cases[0]));
  for (i = 0; i < n; i++)
    if (bits(exp2(cases[i].x)) != cases[i].want) return 100 + i;
  /* exact powers of two must be EXACT, not merely close */
  if (exp2(0.0) != 1.0 || exp2(1.0) != 2.0 || exp2(-1.0) != 0.5) return 90;
  if (exp2(10.0) != 1024.0) return 91;
  return 42;
}
