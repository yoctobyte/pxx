/* SPDX-License-Identifier: Zlib */
/* Payne-Hanek huge-argument trig (feature-crtl-trig-payne-hanek).

   Cody-Waite reduction runs out at 1e8; past that sin/cos/tan used to fall back
   to the Pascal routines, which are 1-ulp-class and badly wrong for
   astronomically large arguments. crtl_trig_reduce_big now reduces properly.

   Every expected value below was judged against a 400-digit reference (pi via
   Machin, argument reduced mod 2pi at full precision, then Taylor) and is the
   CORRECTLY ROUNDED double — all 36 at 0 ulp, alongside a 200-value random
   sweep over [1e8, 1e308] in both signs that was also 0 ulp across all three
   functions.

   Bit patterns, not decimal text, and no printf: printf's float path is what
   this file would be testing with, and it is also currently unavailable under
   the pin (undefined __pxx_fegetround). Comparing raw doubles avoids both.

   Returns 42 on success, or 100+index of the first mismatch. */

#include "math.c"

typedef struct { double x; unsigned long long want; } tcase;

static const tcase sin_cases[] = {
  { 1.0e8,                     0x3fedcffca623a20bULL },
  { 1.0e12,                    0xbfe38f4477984352ULL },
  { 1.0e16,                    0x3fe8f334432ebba5ULL },
  { 1.0e20,                    0xbfe4a5e605fd6450ULL },
  { 1.0e100,                   0xbfd85c5e5b929359ULL },
  { 1.0e300,                   0xbfea2c16b010e385ULL },
  { 123456789.0,               0x3fefaf0521c8dc5cULL },
  { -1.0e20,                   0x3fe4a5e605fd6450ULL },
  { 2.0e300,                   0x3fee1e46a07c8e26ULL },
  { 1.7976931348623157e308,    0x3f7452fc98b34e97ULL },
  { 9007199254740992.0,        0xbfeb2a66c8f35586ULL },
  { 1.0e8 + 0.5,               0x3fe4968538c85a05ULL },
};
static const tcase cos_cases[] = {
  { 1.0e8,                     0xbfd741b388a8c029ULL },
  { 1.0e12,                    0x3fe9538731dff223ULL },
  { 1.0e16,                    0xbfe40991e398dbfcULL },
  { 1.0e20,                    0x3fe872720fc60d3dULL },
  { 1.0e100,                   0x3fed9757496841f5ULL },
  { 1.0e300,                   0xbfe2699022adc4c1ULL },
  { 123456789.0,               0x3fc1f4077c91589fULL },
  { -1.0e20,                   0x3fe872720fc60d3dULL },
  { 2.0e300,                   0xbfd59f86723ed82aULL },
  { 1.7976931348623157e308,    0xbfefffe62ecfab75ULL },
  { 9007199254740992.0,        0xbfe0e9918bb35aacULL },
  { 1.0e8 + 0.5,               0xbfe87f66d2f67428ULL },
};
static const tcase tan_cases[] = {
  { 1.0e8,                     0xc004829e83f49589ULL },
  { 1.0e12,                    0xbfe8b6bb0174398fULL },
  { 1.0e16,                    0xbff3ec3afb0422dfULL },
  { 1.0e20,                    0xbfeb06fbbe995394ULL },
  { 1.0e100,                   0xbfda5807d6f76f7dULL },
  { 1.0e300,                   0x3ff6be411f37ac77ULL },
  { 123456789.0,               0x401c3c92fa621ffcULL },
  { -1.0e20,                   0x3feb06fbbe995394ULL },
  { 2.0e300,                   0xc0064933be899f80ULL },
  { 1.7976931348623157e308,    0xbf74530cfe729484ULL },
  { 9007199254740992.0,        0x3ff9b33af5ae241fULL },
  { 1.0e8 + 0.5,               0xbfeae49a0f3235bcULL },
};

static unsigned long long bits(double d) {
  union { double d; unsigned long long u; } u; u.d = d; return u.u;
}

int main(void) {
  int i, n = (int)(sizeof(sin_cases)/sizeof(sin_cases[0]));
  for (i = 0; i < n; i++)
    if (bits(__crtl_sin(sin_cases[i].x)) != sin_cases[i].want) return 100 + i;
  for (i = 0; i < n; i++)
    if (bits(__crtl_cos(cos_cases[i].x)) != cos_cases[i].want) return 200 + i;
  for (i = 0; i < n; i++)
    if (bits(__crtl_tan(tan_cases[i].x)) != tan_cases[i].want) return 300 + i;
  return 42;
}
