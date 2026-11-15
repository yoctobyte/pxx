/* The address of a 64-bit ARRAY ELEMENT or STRUCT FIELD passed through a
   variadic tail is one pointer, not an 8-byte pair. On a 32-bit target the
   address kept the element's 64-bit tag, so the caller pushed it as two
   words and every following variadic argument read one word late:
   sscanf("%llu %llu", &v[0], &v[1]) segfaulted on i386 (the second pointer
   was the first one's padding word) and printf("%p %d", &v[1], 4) printed 0
   for the 4.
   bug-c-the-address-of-a-64-bit-array-element-is-an-8-byte-vararg-on-32-bit */
#include <stdio.h>
#include <stdarg.h>

struct pair { int tag; long long big; unsigned long long ubig; };

static int addrs(int n, ...) {
  va_list ap; int i, ok = 1; long long *want;
  va_start(ap, n);
  want = va_arg(ap, long long *);
  for (i = 1; i < n; i++) if (va_arg(ap, long long *) != want + i) ok = 0;
  i = va_arg(ap, int);
  va_end(ap);
  return ok && i == 77;
}

int main(void) {
  unsigned long long v[4] = {0, 0, 0, 0};
  long long w[3];
  long long m[2][2];
  struct pair p;
  int got;
  got = sscanf("11 22 33", "%llu %llu %llu", &v[0], &v[1], &v[2]);
  printf("1 %d %llu %llu %llu\n", got, v[0], v[1], v[2]);
  got = sscanf("-5 6", "%lld %llu", &p.big, &p.ubig);
  printf("2 %d %lld %llu\n", got, p.big, p.ubig);
  printf("3 %d\n", addrs(3, &w[0], &w[1], &w[2], 77));
  got = sscanf("7 8", "%lld %lld", &m[1][0], &m[1][1]);
  printf("4 %d %lld %lld\n", got, m[1][0], m[1][1]);
  printf("5 %d %d\n", (int)((char *)&v[1] - (char *)&v[0]), 4);
  return 0;
}
