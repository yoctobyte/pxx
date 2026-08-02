/* math.h's M_* constants. They were simply ABSENT from pxx's own math.h, which
 * an undeclared identifier makes a SILENT wrong value rather than an error:
 * `M_PI` evaluated to 0.0, so anything built on it came out plausible-looking
 * and wrong. Surfaced by vendored pdfgen (lib/vendor/pdfgen), whose circle
 * routine uses the Bezier offset (4/3)*(M_SQRT2-1)*r — with M_SQRT2 at zero
 * that is -1.333*r instead of +0.552*r, wrong in sign AND magnitude, so every
 * circle it emitted was garbage while the PDF around it stayed valid.
 *
 * Expected bit patterns are the correctly rounded IEEE 754 doubles, taken from
 * gcc on the same literals — this pins the VALUES, not just the presence of the
 * macros, so a mis-decoded 21-digit literal fails here too. Verified identical
 * on x86-64, i386, aarch64 and arm32. */
#include <math.h>

typedef unsigned long long u64;

static int chk(double v, u64 want) {
  union { double d; u64 u; } x;
  x.d = v;
  return x.u == want;
}

int main(void) {
  if (!chk(M_E,        0x4005bf0a8b145769ULL)) return 1;
  if (!chk(M_LOG2E,    0x3ff71547652b82feULL)) return 2;
  if (!chk(M_LOG10E,   0x3fdbcb7b1526e50eULL)) return 3;
  if (!chk(M_LN2,      0x3fe62e42fefa39efULL)) return 4;
  if (!chk(M_LN10,     0x40026bb1bbb55516ULL)) return 5;
  if (!chk(M_PI,       0x400921fb54442d18ULL)) return 6;
  if (!chk(M_PI_2,     0x3ff921fb54442d18ULL)) return 7;
  if (!chk(M_PI_4,     0x3fe921fb54442d18ULL)) return 8;
  if (!chk(M_1_PI,     0x3fd45f306dc9c883ULL)) return 9;
  if (!chk(M_2_PI,     0x3fe45f306dc9c883ULL)) return 10;
  if (!chk(M_2_SQRTPI, 0x3ff20dd750429b6dULL)) return 11;
  if (!chk(M_SQRT2,    0x3ff6a09e667f3bcdULL)) return 12;
  if (!chk(M_SQRT1_2,  0x3fe6a09e667f3bcdULL)) return 13;

  /* the pdfgen circle offset itself: (4/3)*(sqrt(2)-1)*r for r = 100 */
  if (!chk((4.0 / 3.0) * (M_SQRT2 - 1) * 100.0,
                       0x404b9d3eab1223d5ULL)) return 14;
  return 0;
}
