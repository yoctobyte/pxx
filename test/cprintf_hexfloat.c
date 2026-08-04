/* printf %a / %A (C99 hex float), the +/space flags on float conversions, and
 * the sign of NAN — three defects found together
 * (bug-b-crtl-printf-hexfloat-and-float-sign-flags).
 *
 * %a WAS A CRASH, not a cosmetic gap. It fell to the unknown-conversion path,
 * which printed the literal "%a" AND did not consume the double. On x86-64 that
 * was invisible — doubles arrive in their own register save area, so the
 * following %d and %s still read the right slots — but on i386, arm32 and
 * riscv32, where varargs walk the stack, everything after it shifted and
 *
 *     printf("[%a] %s\n", 0.5, "tail")
 *
 * SEGFAULTED on a garbage pointer. That is why the mixed-argument lines below
 * matter more than the formatting ones: they are the regression guard, and they
 * only ever failed off x86-64.
 *
 * Whole output diffed against a gcc build — no recorded expectations. The
 * values cover the cases where a plausible implementation goes wrong: zero and
 * negative zero, a SUBNORMAL (printed 0x0.…p-1022, deliberately not
 * renormalised), DBL_MAX, a precision that rounds INTO the leading digit
 * (%.0a of 0.1 is 0x2p-4, not 0x1p-3), and a precision past the 13 available
 * nibbles, which pads with zeros.
 */
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

int main(void) {
  double v[] = {0.0, -0.0, 1.0, 2.0, 0.5, -2.5, 0.1, 3.14159,
                4.9406564584124654e-324,      /* smallest subnormal */
                2.2250738585072014e-308,      /* smallest normal */
                1.7976931348623157e308,       /* DBL_MAX */
                255.0, 1.0 / 3.0};
  int i;

  for (i = 0; i < (int)(sizeof v / sizeof *v); i++)
    printf("[%a][%A]\n", v[i], v[i]);

  /* precision: 0 rounds into the leading digit, 20 pads past the 13 nibbles */
  printf("prec [%.0a][%.1a][%.3a][%.5a][%.13a][%.20a]\n", 0.1, 0.1, 0.1, 0.1, 0.1, 0.1);
  /* rounding direction, both ways */
  printf("rnd  [%.1a][%.1a][%.2a]\n", 0.1, 0.3, 0.1);
  /* '#' keeps the point with no fraction digits */
  printf("alt  [%#a][%a]\n", 1.0, 1.0);
  printf("spec [%a][%a][%a]\n", INFINITY, -INFINITY, NAN);

  /* '+' and ' ' apply to EVERY signed conversion, and the float ones were
     being skipped — %+f printed "1.500000" */
  printf("f  [%+f][% f][%+f]\n", 1.5, 1.5, -1.5);
  printf("e  [%+e][% e][%+e]\n", 1.5, 1.5, -1.5);
  printf("g  [%+g][% g][%+g]\n", 1.5, 1.5, -1.5);
  printf("a  [%+a][% a][%+a]\n", 1.5, 1.5, -1.5);

  /* NAN must be POSITIVE: it was (0.0/0.0), which sets the sign bit on x86, so
     every float conversion rendered it as "-nan" */
  printf("nan [%f][%e][%g][%a]\n", NAN, NAN, NAN, NAN);

  /* THE REGRESSION GUARD: an %a must consume its double, or every argument
     after it shifts. These lines crashed on all three 32-bit targets. */
  printf("mix1 [%a] then %d and %s\n", 0.5, 42, "tail");
  printf("mix2 %d [%a] %d\n", 1, 0.5, 2);
  printf("mix3 [%a] [%a] %d\n", 1.0, 2.0, 7);

  /* AND BACK: %a is only half of a round trip. strtod had no hex-float parsing
     at all -- it stopped at the 'x', returned 0 and left "x1.8p+1" -- so the
     library could print a double exactly and not read it back, which is the
     one thing the format exists for. atof and scanf's %f go through strtod, so
     they were wrong the same way. */
  { char *e; double d;
    d = strtod("0x1.8p+1", &e);  printf("sd1  %.17g [%s]\n", d, e);
    d = strtod("0x10", &e);      printf("sd2  %.17g [%s]\n", d, e);
    d = strtod("-0X1P-1", &e);   printf("sd3  %.17g [%s]\n", d, e);
    /* no hex digits is NOT a hex float: the '0' parses and "x" is left */
    d = strtod("0x", &e);        printf("sd4  %.17g [%s]\n", d, e);
    /* an incomplete exponent is not consumed either */
    d = strtod("0x1p", &e);      printf("sd5  %.17g [%s]\n", d, e);
    /* The ends: DBL_MAX, overflow, the smallest subnormal, and past it.
       TWO OF THESE FAIL ON CROSS TARGETS, for reasons that are NOT this code:
         sd6 on i386/arm32 -- a C cast from a 64-bit integer to double
           truncates to the low 32 bits there
           (bug-c-int64-to-double-cast-truncates-on-32bit, urgent);
         sd8 on riscv32 -- soft-float flushes subnormals to zero.
       The expectations below are the correct ones and are kept as written;
       lib-test runs x86-64, where both are right. Deliberately not weakened to
       whatever the broken targets happen to produce. */
    d = strtod("0x1.fffffffffffffp+1023", &e); printf("sd6  %.17g\n", d);
    d = strtod("0x1p+1024", &e); printf("sd7  %.17g\n", d);
    d = strtod("0x1p-1074", &e); printf("sd8  %.17g\n", d);
    d = strtod("0x1p-1075", &e); printf("sd9  %.17g\n", d);
    /* ties at 53 bits, both directions -- half-to-even */
    d = strtod("0x1.00000000000008p+0", &e); printf("sd10 %.17g\n", d);
    d = strtod("0x1.00000000000018p+0", &e); printf("sd11 %.17g\n", d);
    printf("sd12 %.17g\n", atof("0x1.8p+1"));
  }
  { double x = -1; int n = sscanf("0x1.8p+1", "%lf", &x);
    printf("scan %d %.17g\n", n, x); }

  /* the actual round trip: print with %a, read back, must be the same double */
  { char b[64]; double back; int i2;
    double rt[] = {0.1, 3.14159, 1.0/3.0, 1e-300, 1e300, 0.0, -2.5};
    for (i2 = 0; i2 < 7; i2++) {
      sprintf(b, "%a", rt[i2]);
      back = strtod(b, 0);
      printf("rt%d %d\n", i2, back == rt[i2]);
    }
  }

  return 0;
}
