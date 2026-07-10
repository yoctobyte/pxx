/* SPDX-License-Identifier: Zlib */
/* Regression b240 (bug-c-duktape-double-formatting residual #3): RTL Sqrt is
   now correctly-rounded (IEEE / hardware-identical), not ~1 ULP low. The old
   software Newton-Raphson had an FP fixed point 1 ULP below the true root
   (sqrt(2) landed ...bcc vs IEEE ...bcd), and the 200-iteration cap never
   converged for large/small exponents. Bit-hack seed + Dekker-exact-residual
   correction fix both. Exit 42 = all bit-exact vs the known IEEE doubles. */
#include "math.c"

static unsigned long long bits(double d) {
  union { double d; unsigned long long u; } x; x.d = d; return x.u;
}

int main(void) {
  if (bits(sqrt(2.0))  != 0x3ff6a09e667f3bcdULL) return 1;  /* 1.4142135623730951 */
  if (bits(sqrt(3.0))  != 0x3ffbb67ae8584caaULL) return 2;  /* 1.7320508075688772 */
  if (bits(sqrt(0.5))  != 0x3fe6a09e667f3bcdULL) return 3;  /* 0.7071067811865476 */
  if (bits(sqrt(1e300))!= 0x5f138d352e5096afULL) return 4;  /* large exponent */
  if (bits(sqrt(1e-300))!=0x20ca2fe76a3f9475ULL) return 5;  /* small exponent */
  if (sqrt(4.0)  != 2.0) return 6;                           /* exact */
  if (sqrt(0.0)  != 0.0) return 7;
  if (sqrt(1.0)  != 1.0) return 8;
  return 42;
}
