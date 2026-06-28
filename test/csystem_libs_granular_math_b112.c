/* Granular --system-libs=m: math is a real DT_NEEDED libm import, while
   string.h stays on the bundled crtl path. Exit 39. */
#include <math.h>
#include <string.h>

int main(void) {
  double a = sqrt(16.0);       /* 4 */
  double b = pow(2.0, 5.0);    /* 32 */
  int c = (int)strlen("abc");  /* 3, from bundled crtl string.c */
  return (int)(a + b) + c;
}
