/* printf's '0' flag on a negative float pads AFTER the sign, and strtod reads
   inf/infinity/nan. Expected output is gcc's.

   Both came from toybox's suite (bug-c-toybox-test-suite-failures): `seq -w
   -2 19 120' printed "0-2" (crtl put the zeros in front of the '-' the float
   formatter emits), and `sort -g' ordered NaN/-inf/+infinity as zeros
   (strtod had no inf or nan at all). glibc also pads inf/nan with spaces and
   ignores '0' for %s, which crtl did not. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void rd(const char *s)
{
  char *e;
  double d;
  errno = 0;
  d = strtod(s, &e);
  /* NaN printed by hand: the sign of a NaN is what is being tested, and %f
     of a NaN is "nan" or "-nan" in glibc, which is what crtl must match. */
  printf("strtod %-14s -> %f used=%d errno=%d\n", s, d, (int)(e - s),
         errno == ERANGE);
}

static void rdf(const char *s)
{
  char *e;
  float f;
  errno = 0;
  f = strtof(s, &e);
  printf("strtof %-14s -> %f used=%d errno=%d\n", s, (double)f, (int)(e - s),
         errno == ERANGE);
}

int main(void)
{
  printf("[%03d] [%05d] [%+05d] [% 05d] [%-05d]\n", -2, -42, 42, 42, -2);
  printf("[%03.0f] [%07.2f] [%+07.2f] [%07.2f] [%07.2e]\n", -2.0, -3.14159,
         3.14159, 3.14159, -3.14159);
  printf("[%0*.*f] [%0*d]\n", 3, 0, -2.0, 4, -7);
  printf("[%05x] [%#06x] [%05s] [%03c]\n", 255, 255, "ab", 'z');
  printf("[%08.3d] [%03ld] [%05lld]\n", -5, -2L, -3LL);
  printf("[%07g] [%07G] [%010.3g] [%-08.2f|]\n", -1.5, -1e-10, -12345.678, -1.5);
  printf("[%05f] [%06f] [%06f] [%+06f]\n", -0.0, 1.0 / 0.0, -1.0 / 0.0, 1.0 / 0.0);
  rd("NaN");
  rd("-nan");
  rd("nan(123)");
  rd("nan(");
  rd("NAN(abc_9)x");
  rd("inf");
  rd("-INF");
  rd("+infinity");
  rd("inFINity!");
  rd("infinit");
  rd("  -inf");
  rd("in");
  rd("bork");
  rd("1.222");
  rd("1e400");
  rdf("inf");
  rdf("-infinity");
  rdf("1e39");
  rdf("nan");
  return 0;
}
