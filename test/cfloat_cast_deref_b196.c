/* Regression (bug-c-double-ptr-deref-narrow-to-single): an explicit float-class
 * cast of a pointer DEREFERENCE — `(float)*doubleptr` / `(double)*floatptr` —
 * used to retag the deref's LOAD node in place (ir.inc AN_PTR_CAST), turning an
 * 8-byte double load into a 4-byte single load (or vice-versa) and reading
 * garbage (observed 0.0). Non-deref casts and implicit narrowing were fine; the
 * bug needed a memory load as the cast operand. Fixed by not reinterpreting a
 * float<->float cast (the value is double bits in a register; the store narrows
 * by dest type). Returns 42 = (int)(*dp narrowed) + 0. */
#include <stdio.h>
static double gd = 42.25;
static float  gf = 100.5f;
int main(void) {
  double *dp = &gd;
  float  *fp = &gf;
  float  n = (float)*dp;    /* narrow: was 0.0, must be 42.25 */
  double w = (double)*fp;   /* widen:  was 0.0, must be 100.5 */
  printf("n=%f w=%f\n", n, w);
  if (n < 42.0f || n > 43.0f) return 1;
  if (w < 100.0 || w > 101.0) return 2;
  return (int)n;            /* 42 */
}
