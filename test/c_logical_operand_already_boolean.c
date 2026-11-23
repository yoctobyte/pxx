/* `&&`, `||` and `!` on operands that are already 0/1 (comparisons, other
 * logical operators) are not compared with 0 again; operands that are not
 * (plain ints, bitwise & and |, pointers, floats) still are. Values against gcc.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
#include <stdbool.h>
static int calls;
static int side(int v) { calls++; return v; }
int main(void) {
  volatile int a = 3, b = 5, z = 0, m = -1;
  volatile unsigned u = 4000000000u;
  volatile double d = 0.5, nz = -0.0, nan = 0.0 / 0.0;
  int arr[2] = { 1, 2 };
  int *p = arr, *np = 0;
  int r1 = a < b && b < 9;
  int r2 = a > b || b == 5;
  int r3 = (a < b) & (b < 9);
  int r4 = (a & 2) && (b & 4);
  int r5 = (a | 4) || z;
  int r6 = a && b;
  int r7 = (a & b) && (a | b);
  int r8 = (a < b && b < 9) || (z && side(1));
  int r9 = !(a < b) || !!a;
  int r10 = p && !np && (p != np);
  int r11 = d && !nz && (nan != nan);
  int r12 = (u > 1u) && (m < 0) && (u < 4000000001u);
  bool t = a < b && b > a;
  int r13 = t && (a == 3);
  int r14 = (a < b) + (a < b && b < 9) + (a & 6);
  int r15 = side(0) && side(1);
  printf("%d %d %d %d %d %d %d %d\n", r1, r2, r3, r4, r5, r6, r7, r8);
  printf("%d %d %d %d %d %d %d\n", r9, r10, r11, r12, r13, r14, r15);
  int f1 = a < b && b > 9;
  int f2 = a > b || z != 0;
  int f3 = (a & 4) && (a < b);
  int f4 = !(a < b && b < 9);
  int f5 = ((a < b) || z) * 10 + ((a & 1) && (b & 1)) * 100 + ((a & 2) || 0) * 1000;
  printf("%d %d %d %d %d\n", f1, f2, f3, f4, f5);
  printf("calls %d\n", calls);
  return 0;
}
