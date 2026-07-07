/* Regression: calling a VARIADIC function through a function pointer must pass
   the args beyond the declared params (the `...` tail). Before the fix the
   indirect cdecl path sized the call by ParamCount and dropped every variadic
   arg (00189: fprintf via pointer printed 0). Own variadic fn keeps this
   deterministic and crtl-free. */
#include <stdarg.h>

int sum(int n, ...) {
  va_list ap;
  int i, s = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, int);
  va_end(ap);
  return s;
}

int main(void) {
  int (*p)(int, ...) = sum;
  if (p(3, 10, 20, 12) != 42) return 1;   /* 3 variadic ints past the count */
  if (p(0) != 0) return 2;                /* no variadic args */
  if (p(1, 42) != 42) return 3;
  return 42;
}
