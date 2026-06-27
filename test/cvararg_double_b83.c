#include <stdarg.h>
/* A double passed variadically rides XMM0 and is read from the FP save area. */
static double vf(int n, ...) {
  va_list ap; double d;
  va_start(ap, n);
  d = va_arg(ap, double);
  va_end(ap);
  return d;
}
int main(void) {
  double r = vf(1, 2.5);
  long b = *(long *)&r;
  return (r == 2.5 && (b >> 32) != 0) ? 42 : 1;
}
