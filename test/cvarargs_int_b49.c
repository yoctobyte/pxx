/* C varargs: integer va_arg over the System V register-save prologue + pure-C
   __pxx_va_* helpers. Exit 42. */
#include <stdarg.h>
static int vsum(int n, ...) {
  va_list ap; va_start(ap, n);
  int s = 0, i;
  for (i = 0; i < n; i++) s += va_arg(ap, int);
  va_end(ap);
  return s;
}
int main(void) { return vsum(4, 10, 12, 11, 9); }   /* 42 */
