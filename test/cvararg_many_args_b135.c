#include "stdio.c"

static int sum_ints(int n, ...) {
  va_list ap;
  int i;
  int s = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, int);
  va_end(ap);
  return s;
}

static int sum_doubles(int n, ...) {
  va_list ap;
  int i;
  double s = 0.0;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, double);
  va_end(ap);
  return (int)s;
}

static int sum_mixed(int n, ...) {
  va_list ap;
  int i;
  int s = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) {
    s += va_arg(ap, int);
    s += (int)va_arg(ap, double);
  }
  va_end(ap);
  return s;
}

int main(void) {
  int a = sum_ints(24,
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24);
  int b = sum_doubles(12,
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0,
    7.0, 8.0, 9.0, 10.0, 11.0, 12.0);
  int c = sum_mixed(10,
    1, 1.0, 2, 2.0, 3, 3.0, 4, 4.0, 5, 5.0,
    6, 6.0, 7, 7.0, 8, 8.0, 9, 9.0, 10, 10.0);

  printf("%d %d %d\n", a, b, c);
  printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    1, 2, 3, 4, 5, 6, 7, 8, 9,
    10, 11, 12, 13, 14, 15, 16, 17, 18);
  return (a == 300 && b == 78 && c == 110) ? 42 : 1;
}
