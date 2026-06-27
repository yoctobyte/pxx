/* Auto-pull of the libc-free crtl implementation. pxx has no separate link step,
   so when a crtl <header> resolves, the compiler also pulls its sibling
   lib/crtl/src/<name>.c impl. Here a bare `#include <math.h>` — NO -I flags, NO
   unity `#include "math.c"` — must make fabs/sqrt/pow resolve to the libc-free
   Pascal-bridged bodies (math.pas), producing a binary with no DT_NEEDED.
   Previously this left fabs as an unresolved libm extern. Exit 42. */
#include <math.h>

int main(void) {
  double a = fabs(-3.0);      /* 3  */
  double b = sqrt(16.0);      /* 4  */
  double c = pow(2.0, 5.0);   /* 32 */
  double d = floor(3.9);      /* 3  */
  return (int)(a + b + c + d); /* 3+4+32+3 = 42 */
}
