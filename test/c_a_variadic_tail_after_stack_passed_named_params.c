/* A VARIADIC TAIL AFTER STACK-PASSED NAMED PARAMETERS READS THE TAIL.
 *
 * On the 32-bit register-passing targets (arm32: r0-r3, riscv32: a0-a7) the
 * va_start seed capped the named bytes at the register area, so once the
 * named parameters spilled to the stack va_arg read THEM again instead of the
 * variadic words. arm32 also skipped AAPCS's 8-byte alignment of a named
 * double or long long. cvararg_stack_spill printed garbage on both.
 * bug-c-a-variadic-tail-after-stack-passed-named-params-reads-the-named-words
 *
 * The sums are the same on every target: one .expected file serves native
 * and all four cross targets, and native is diffed against gcc.
 */
#include <stdio.h>
#include <stdarg.h>

/* a double in the named list (padded on arm32), mixed int/double tail */
static double f1(int a, double d, int b, int c, int n, ...) {
  va_list ap; double s = 0; int k; va_start(ap, n);
  for (k = 0; k < n; k++) s += (k & 1) ? va_arg(ap, double) : va_arg(ap, int);
  va_end(ap); return a + d * 10 + b * 100 + c * 1000 + s;
}
/* a long long named after an int (padded), long long tail */
static long long f2(int a, long long x, int n, ...) {
  va_list ap; long long s = 0; int k; va_start(ap, n);
  for (k = 0; k < n; k++) s += va_arg(ap, long long);
  va_end(ap); return a + x + s;
}
/* six named ints: past r0-r3 on arm32 */
static int f3(int a, int b, int c, int d, int e, int n, ...) {
  va_list ap; int s = 0, k; va_start(ap, n);
  for (k = 0; k < n; k++) s = s * 10 + va_arg(ap, int);
  va_end(ap); return s + a + b + c + d + e;
}
/* nine named ints: past a0-a7 on riscv32 as well */
static int f4(int a, int b, int c, int d, int e, int f, int g, int h, int n, ...) {
  va_list ap; int s = 0, k; va_start(ap, n);
  for (k = 0; k < n; k++) s = s * 10 + va_arg(ap, int);
  va_end(ap); return s * 1000 + a + b + c + d + e + f + g + h;
}
/* the tail is walked twice, through va_copy */
static int f5(int a, int b, int c, int d, int e, int n, ...) {
  va_list ap, aq; int s = 0, t = 0, k; va_start(ap, n); va_copy(aq, ap);
  for (k = 0; k < n; k++) s += va_arg(ap, int);
  for (k = 0; k < n; k++) t = t * 10 + va_arg(aq, int);
  va_end(aq); va_end(ap); return s * 10000 + t + a * 0 + b * 0 + c * 0 + d * 0 + e * 0;
}

int main(void) {
  printf("%.2f\n", f1(1, 2.5, 3, 4, 4, 5, 0.25, 7, 0.5));
  printf("%lld\n", f2(1, 1000000000000LL, 3, 2LL, 30000000000LL, 400LL));
  printf("%d\n", f3(1, 2, 3, 4, 5, 3, 7, 8, 9));
  printf("%d\n", f4(1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 6));
  printf("%d\n", f5(9, 9, 9, 9, 9, 3, 1, 2, 3));
  return 0;
}
