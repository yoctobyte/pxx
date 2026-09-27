/* A FLOATING CONDITION TESTS ITS VALUE, NOT ITS BITS.
 *
 * `if (d)`, `while (d)`, `for (;d;)` and `d ? x : y` with a double or float d
 * branched on the register bits: -0.0 (sign bit set) was TRUE on every target,
 * and on i386 and arm32 `f ? 1 : 2`, `if ((t = f))` and a 0.5 were wrong too
 * (0.5 read as false). `!d`, `&&` and `||` were already right.
 * bug-c-a-floating-condition-branches-on-its-bits
 *
 * The answers are C's, identical on every target: one .expected file serves
 * native and all four cross targets, and native is diffed against gcc.
 */
#include <stdio.h>

#define R(e) printf("%s = %d\n", #e, (int)(e))

static int cnt_while(double d) { int n = 0; while (d) { n++; if (n > 2) break; } return n; }
static int cnt_for(double d) { int n = 0; for (; d; ) { n++; if (n > 2) break; } return n; }
static int cnt_do(double d) { int n = 0; do { n++; if (n > 2) break; } while (d); return n; }
static int cnt_forf(float f) { int n = 0; for (; f; ) { n++; if (n > 2) break; } return n; }

int main(void) {
  volatile double nz = -0.0, pz = 0.0, half = 0.5, tiny = 1e-300, nan = 0.0 / 0.0;
  volatile float nzf = -0.0f, halff = 0.5f;
  double t; float u;
  int k;
  R(nz ? 1 : 2); R(pz ? 1 : 2); R(half ? 1 : 2); R(tiny ? 1 : 2); R(nan ? 1 : 2);
  R(nzf ? 1 : 2); R(halff ? 1 : 2);
  R(!nz); R(nz && 1); R(nz || 0); R(half && 1);
  k = 0; if (nz) k = 1; R(k);
  k = 0; if (half) k = 1; R(k);
  k = 0; if (nzf) k = 1; R(k);
  k = 0; if ((t = nz)) k = 1; R(k);
  k = 0; if ((u = halff)) k = 1; R(k);
  R((t = pz) ? 1 : 2); R((u = halff) ? 1 : 2);
  R(cnt_while(nz)); R(cnt_while(half));
  R(cnt_for(nz)); R(cnt_for(half));
  R(cnt_do(nz)); R(cnt_do(half));
  R(cnt_forf(nzf)); R(cnt_forf(halff));
  return 0;
}
