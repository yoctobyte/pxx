/* sscanf's return contract and the math surface
 * (feature-crtl-implement-libc-assumptions, round 5).
 *
 * sscanf returned 0 where C requires EOF: an INPUT failure before any
 * conversion is -1, while 0 means input was available and did not match.
 * Callers depend on it — `while (sscanf(...) != EOF)` terminates on the first
 * and spins forever on the second.
 *
 * The boundary cases below are the whole point. "Input exhausted" is measured
 * after LEADING WHITESPACE (scanf skips it before every conversion, so a
 * whitespace-only string is EOF too) and from the START of the input, because
 * sscanf("abc", "abc") consumed its input successfully and must return 0 even
 * though it ends at the terminator having assigned nothing.
 *
 * Diffed whole against the same file built by gcc.
 */
#include <stdio.h>
#include <math.h>
#include <string.h>

int main(void) {
  int a = 0, b = 0, n; char s1[32] = "", s2[32] = ""; double d = 0;
  long l = 0; unsigned u = 0;

  /* the return contract, including every boundary that distinguishes EOF from 0 */
  printf("empty_fmt_empty=%d\n",  sscanf("", ""));          /* 0: nothing asked */
  printf("empty_fmt_input=%d\n",  sscanf("x", ""));         /* 0 */
  printf("empty_in_d=%d\n",       sscanf("", "%d", &a));    /* EOF */
  printf("empty_in_s=%d\n",       sscanf("", "%s", s1));    /* EOF */
  printf("empty_in_lit=%d\n",     sscanf("", "abc"));       /* EOF */
  printf("ws_only_in_d=%d\n",     sscanf("   ", "%d", &a)); /* EOF: ws skipped */
  printf("nomatch_nonempty=%d\n", sscanf("abc", "%d", &a)); /* 0: had input */
  printf("lit_only_match=%d\n",   sscanf("abc", "abc"));    /* 0: consumed it */
  printf("partial=%d\n",          sscanf("1", "%d %d", &a, &a));
  printf("suppress_empty=%d\n",   sscanf("", "%*d"));       /* EOF */

  /* ordinary conversions, so the EOF work cannot regress them */
  n = sscanf("12 34", "%d %d", &a, &b);        printf("two=%d %d %d\n", n, a, b);
  n = sscanf("hello world", "%s %s", s1, s2);  printf("str=%d [%s][%s]\n", n, s1, s2);
  n = sscanf("3.25", "%lf", &d);               printf("dbl=%d %.4g\n", n, d);
  n = sscanf("ff", "%x", &u);                  printf("hex=%d %u\n", n, u);
  n = sscanf("  42", "%ld", &l);               printf("lead_ws=%d %ld\n", n, l);
  memset(s1, 0, sizeof(s1));
  n = sscanf("abcdef", "%3s", s1);             printf("width=%d [%s]\n", n, s1);
  n = sscanf("12abc", "%d%s", &a, s1);         printf("adjacent=%d %d [%s]\n", n, a, s1);
  n = sscanf("a=5", "a=%d", &a);               printf("literal=%d %d\n", n, a);
  printf("lit_mismatch=%d\n",     sscanf("x 7", "y %d", &a));

  /* math values and special cases */
  printf("fmod=%.6g %.6g\n", fmod(7.0, 3.0), fmod(-7.0, 3.0));
  printf("hypot=%.6g log2=%.6g\n", hypot(3.0, 4.0), log2(8.0));
  printf("copysign=%.1f %.1f\n", copysign(2.0, -1.0), copysign(-2.0, 1.0));
  printf("floor/ceil=%.1f %.1f %.1f %.1f\n",
         floor(1.5), floor(-1.5), ceil(1.5), ceil(-1.5));
  printf("trunc/round=%.1f %.1f %.1f %.1f\n",
         trunc(-1.7), trunc(1.7), round(-1.5), round(1.5));
  printf("pow=%.6g %.6g\n", pow(2.0, 10.0), pow(2.0, 0.5));
  printf("sqrt=%.10g exp=%.10g log=%.10g\n",
         sqrt(2.0), exp(1.0), log(2.718281828459045));
  printf("nan/inf=%d %d %d\n",
         isnan(0.0 / 0.0) != 0, isinf(1.0 / 0.0) != 0, isinf(-1.0 / 0.0) != 0);
  printf("fabs=%.1f %.1f\n", fabs(-3.5), fabs(3.5));
  return 0;
}
