/* crtl functions the Athena apps need: finite/finitef (xedit's Lisp),
   sincos/sincosf (xclock), getloadavg (xload), gettext and friends with no
   catalogue (xload), MB_LEN_MAX (xclock), and strcasecmp from a plain
   <string.h> with no feature macro (xedit's Lisp; glibc's _DEFAULT_SOURCE is
   implied). Output matches gcc.
   feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools (follow-up) */
#include <libintl.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern void sincos(double, double *, double *);
extern void sincosf(float, float *, float *);
extern int finite(double);
extern int finitef(float);
int main(void)
{
  double s, c, la[3];
  float sf, cf;
  volatile double zero = 0.0;
  int n;
  sincos(0.5, &s, &c);
  sincosf(0.5f, &sf, &cf);
  printf("%.6f %.6f %.4f %.4f\n", s, c, sf, cf);
  printf("%d %d %d %d\n", finite(1.0), finite(1.0 / zero), finite(zero / zero), finitef(2.0f));
  n = getloadavg(la, 3);
  printf("%d %d %d\n", n, la[0] >= 0 && la[2] >= 0, getloadavg(la, 1));
  printf("[%s] [%s] [%s]\n", gettext("hello"), ngettext("one", "many", 1), ngettext("one", "many", 3));
  printf("[%s] [%s]\n", dgettext("dom", "msg"), textdomain("pxxtest"));
  printf("%d %d\n", MB_LEN_MAX >= 4, strcasecmp("HeLLo", "hello"));
  return 0;
}
