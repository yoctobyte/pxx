/* Regression: __builtin_va_copy duplicates a va_list; both walks see the same args. */
#include <stdio.h>
#include <stdarg.h>
static int sum2(int n, ...) {
  va_list a, b;
  va_start(a, n);
  va_copy(b, a);              /* b is an independent copy of a */
  int s = 0, i;
  for (i = 0; i < n; i++) s += va_arg(a, int);   /* walk a */
  for (i = 0; i < n; i++) s += va_arg(b, int);   /* walk b -> same values again */
  va_end(a); va_end(b);
  return s;                    /* (1+2+3)*2 = 12 */
}
int main(void){ printf("%d\n", sum2(3, 1, 2, 3)); return sum2(3,1,2,3)==12?42:1; }
