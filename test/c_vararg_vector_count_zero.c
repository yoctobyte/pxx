/* x86-64 sets al (vector registers used) before a C call with `xor eax, eax`
 * when it is 0, `mov eax, n` otherwise (row c_vacnt26 counts `mov $0x0,%eax`).
 * Variadic callees, direct and through a pointer, with and without doubles,
 * against gcc. feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
#include <stdarg.h>
static double sum(int n, ...) {
  va_list ap; double s = 0; int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, double);
  va_end(ap);
  return s;
}
static long isum(int n, ...) {
  va_list ap; long s = 0; int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, long);
  va_end(ap);
  return s;
}
int main(void) {
  int (*pf)(const char *, ...) = printf;
  long (*pi)(int, ...) = isum;
  double (*pd)(int, ...) = sum;
  int a = 3, b = 4;
  printf("%d %d\n", a, b);
  printf("%.2f %d %.3f\n", 1.5, a, 2.25);
  pf("%s %d\n", "ptr", a < b);
  pf("%.1f\n", 9.5);
  printf("%ld %ld\n", isum(3, 1L, 2L, 3L), pi(2, 10L, 20L));
  printf("%.2f %.2f\n", sum(3, 1.0, 2.5, 3.5), pd(1, 0.25));
  if (a < b) printf("cmp-then-call %d\n", isum(1, 7L));
  return 0;
}
