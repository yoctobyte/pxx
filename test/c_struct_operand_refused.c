/* A struct, a union or a _Complex value is not an operand of a scalar
   operator; gcc refuses every case below, and pxx compiled them silently.
   CASE=0 is the legal neighbourhood, which must still compile and run: struct
   assignment, a struct through the comma operator and through ?:, member
   access, and _Complex objects copied and passed.
   bug-c-struct-operands-to-scalar-operators-compile-silently,
   feature-c-complex-types-as-layout */
#include <stdio.h>
#include <string.h>
struct S { double x, y; };
union U { int i; float f; };

static _Complex double pass(_Complex double z) { return z; }

int main(void) {
  struct S a = { 1, 2 }, b = { 3, 4 };
  union U u = { 5 };
  _Complex double z, w;
  double r = 0, p[2] = { 6, 7 };
  memcpy(&z, p, sizeof p);
  w = pass(z);
#if CASE == 0
  a = b;
  r = (1, a).x + (r ? a : b).y + u.i;
  memcpy(p, &w, sizeof p);
  printf("%g %g %g\n", r, p[0], p[1]);
#elif CASE == 1
  r = (a + b).x;
#elif CASE == 2
  if (a == b) r = 1;
#elif CASE == 3
  r = -a.x + -u;
#elif CASE == 4
  r = !a;
#elif CASE == 5
  if (u) r = 1;
#elif CASE == 6
  r = (double)a;
#elif CASE == 7
  a = 1.0;
#elif CASE == 8
  r = a.x ? 1 : 0; r = b ? 1 : 0;
#elif CASE == 9
  w = z + w;
#elif CASE == 10
  w = z * 2.0;
#elif CASE == 11
  r = (double)z;
#elif CASE == 12
  z = 1.0;
#elif CASE == 13
  z = (_Complex double)r;
#endif
  return (int)r;
}
