#include "stdio.c"

static int last_int(int n, ...) {
  va_list ap;
  int i;
  int x = 0;

  va_start(ap, n);
  for (i = 0; i < n; i++) x = va_arg(ap, int);
  va_end(ap);
  return x;
}

int main(void) {
  printf("%d %d %d %d %d %d\n", 1, 2, 3, 4, 5, 6);
  printf("%d %d\n", last_int(7, 1, 2, 3, 4, 5, 6, 7),
                    last_int(8, 1, 2, 3, 4, 5, 6, 7, 8));
  return 42;
}
