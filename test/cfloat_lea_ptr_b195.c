/* Regression (bug-c-sqlite-suite-runtime-segfault): taking the address of a
 * single/float-typed lvalue produces an IR_LEA node that is tagged with its
 * ELEMENT type (tySingle), not tyPointer. When that address was stored into a
 * pointer variable, C-mode's float->int truncation (cvttsd2si, added for 00175)
 * misfired on the pointer VALUE and corrupted it — sqlite3AtoF crashed on the
 * first `*z` after `zEnd = z + length`-style pointer setup. The fix excludes
 * IR_LEA values from float->int truncation. Here: store &float / &double into
 * pointers and dereference — must not crash and must read the real values.
 * Returns 142 = (int)(100.5 + 42.0) via the pointers. */
#include <stdio.h>
static float  gf = 100.5f;
static double gd = 42.0;
int main(void) {
  float  *pf = &gf;   /* IR_LEA(tySingle) -> pointer: the crash trigger */
  double *pd = &gd;
  printf("pf=%f pd=%f\n", *pf, *pd);
  int r = (int)*pf + (int)*pd;   /* 100 + 42 */
  return r;
}
