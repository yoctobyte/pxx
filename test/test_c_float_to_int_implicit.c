/* IMPLICIT float->integer conversion in C (C11 6.3.1.4: truncate toward
 * zero). The C frontend leaves the conversion to the STORE, so each backend's
 * store arms must do it. xtensa stored raw bits (`int x = 99.0` was 0) and
 * riscv32 read a float RHS as a double (`int w = floatvar` was 0); c-testsuite
 * 00175. Every shape the store arms distinguish: a scalar, a struct field, an
 * array element, a long long, a char, a call argument, a return value, an unsigned destination, single and double sources, negatives. */
#include <stdio.h>

struct S { int i; long long ll; char c; };

static int fi(int a) { return a; }
static long long fl(long long a) { return a; }
static int ret(double v) { return v; }
static long long retll(float v) { return v; }

int main(void) {
  double d = 99.75, nd = -42.9; float g = 98.5f, ng = -7.25f;
  int x = 99.0; int y = d; int w = g; int nw = ng; char c = 97.0;
  long long ll = d; long long big = 3.0e12; long long nb = -3.0e12;
  struct S s; int a[3];
  s.i = d; s.ll = nd; s.c = g;
  a[0] = g; a[1] = nd; a[2] = 1.0e9;
  printf("%d %d %d %d %d %lld %lld %lld\n", x, y, w, nw, c, ll, big, nb);
  printf("%d %lld %d %d %d %d\n", s.i, s.ll, s.c, a[0], a[1], a[2]);
  unsigned u = 3.0e9; unsigned short us = 65000.7;
  printf("%d %d %d %lld\n", fi(99.0), fi(g), fi(nd), fl(d));
  printf("%d %lld %u %u\n", ret(-12.99), retll(1.0e10f), u, us);
  return 0;
}
