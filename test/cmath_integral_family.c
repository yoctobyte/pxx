/* SPDX-License-Identifier: Zlib */
/*
 * The integral-part family — fabs/trunc/round/rint/frexp/modf — at the two
 * boundaries the loop-form implementations used to get wrong, plus one hang.
 *
 * bug-b-crtl-integral-math-loses-the-sign-of-zero-and-breaks-past-2p63. All six
 * were ONE bug wearing six hats: floor/ceil had already been given a |x| >= 2^52
 * early return and an explicit -0.0 restore, and nothing else in the file had
 * been brought along. So this test covers the whole family in one place, on the
 * principle that fixing one arm of a double case is how the other arm stays
 * broken (devdocs/dev/normalise-dont-special-case.md).
 *
 * What each row is for:
 *
 * - SIGNED ZERO is observable — through printf and through signbit — so it is a
 *   real wrong answer, not a cosmetic one. `fabs` is defined as CLEARING the
 *   sign bit; written as `x < 0.0 ? -x : x` it missed -0.0, because -0.0 is not
 *   less than zero. The others lost it in a (long long) round trip.
 *
 * - PAST 2^52 the cast is undefined and answered -2^63 (so trunc(1e300) came
 *   back as -9.2e18, a wrong MAGNITUDE rather than a wrong sign). Every double
 *   that large is already an integer, so the answer is the argument.
 *
 * - round(0.49999999999999994) is a separate bug in the same function: the old
 *   body cast `x + 0.5`, and for the double just below 0.5 that sum rounds UP
 *   to exactly 1.0, giving 1 where C requires 0. Comparing against the fraction
 *   never adds and so cannot round.
 *
 * - frexp(inf) HUNG. `while (a >= 1.0) a = a * 0.5` does not terminate for an
 *   infinity, so this row is a liveness check, not a value check — it is why
 *   the test would time out rather than fail if that guard is removed.
 *
 * Expectations are gcc -O1 -lm's own output, and the full 22-argument x
 * 8-function sweep this was cut down from matches gcc bit-for-bit on x86-64 and
 * on i386.
 */
#include <stdio.h>
#include <math.h>

/* Print the sign explicitly: "%g" alone renders +0.0 and -0.0 identically on
   some libcs, which would make the very thing under test invisible. */
static void p(const char *tag, double v) {
  printf("%s=%s%g\n", tag, signbit(v) ? "-" : "+", fabs(v));
}

int main(void) {
  double ip, fr;
  int e;

  p("fabs(-0)", fabs(-0.0));
  p("trunc(-0.5)", trunc(-0.5));
  p("round(-0)", round(-0.0));
  p("rint(-0.5)", rint(-0.5));

  fr = frexp(-0.0, &e);
  printf("frexp(-0)=%s%g e=%d\n", signbit(fr) ? "-" : "+", fabs(fr), e);

  fr = modf(-1.0, &ip);
  printf("modf(-1) fr=%s%g ip=%s%g\n", signbit(fr) ? "-" : "+", fabs(fr),
         signbit(ip) ? "-" : "+", fabs(ip));

  p("trunc(1e300)", trunc(1e300));
  p("round(-1e300)", round(-1e300));

  fr = modf(1e300, &ip);
  printf("modf(1e300) fr=%s%g ip=%s%g\n", signbit(fr) ? "-" : "+", fabs(fr),
         signbit(ip) ? "-" : "+", fabs(ip));

  p("round(0.49999999999999994)", round(0.49999999999999994));

  /* liveness: the old frexp never returned here */
  p("frexp(inf)", frexp(1.0 / 0.0, &e));

  return 0;
}
