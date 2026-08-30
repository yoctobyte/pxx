/* Control flow the codegen and the token stream both touch: a Duff's device,
   deeply nested blocks, a switch whose cases live inside other statements,
   goto, varargs, and recursion. Deterministic output, no libm, no syscalls
   beyond stdio. */
#include <stdio.h>
#include <stdarg.h>

static unsigned long h = 1469598103u;
static void mix(long v) { h = (h ^ (unsigned long)v) * 16777619u; }

static void duff(char *dst, const char *src, int n) {
  int q = (n + 7) / 8;
  if (n <= 0) return;
  switch (n % 8) {
  case 0: do { *dst++ = *src++;
  case 7:      *dst++ = *src++;
  case 6:      *dst++ = *src++;
  case 5:      *dst++ = *src++;
  case 4:      *dst++ = *src++;
  case 3:      *dst++ = *src++;
  case 2:      *dst++ = *src++;
  case 1:      *dst++ = *src++;
          } while (--q > 0);
  }
}

static int sum_va(int count, ...) {
  va_list ap; int i, t = 0;
  va_start(ap, count);
  for (i = 0; i < count; i++) t += va_arg(ap, int);
  va_end(ap);
  return t;
}

static long ack(int m, long n) {
  if (m == 0) return n + 1;
  if (n == 0) return ack(m - 1, 1);
  return ack(m - 1, ack(m, n - 1));
}

int main(void) {
  char buf[64];
  const char *src = "the quick brown fox jumped over 13 lazy dogs!!";
  int i, j, k, n = 0;

  duff(buf, src, 45);
  buf[45] = '\0';
  printf("duff %s\n", buf);

  for (i = 0; i < 6; i++)
    for (j = 0; j < 6; j++) {
      if ((i ^ j) == 3) continue;
      for (k = 0; k < 3; k++) {
        if (i * j * k > 40) goto done;
        switch ((i + j + k) % 5) {
        case 0: mix(i); break;
        case 1: mix(j * 3); break;
        case 2: mix(k - i); /* fallthrough */
        case 3: mix(1); break;
        default: mix(-1);
        }
        n++;
      }
    }
done:
  printf("loops %d hash %lu\n", n, h & 0xffffffful);
  printf("va %d %d %d\n", sum_va(0), sum_va(3, 1, 2, 3), sum_va(6, 10, 20, 30, 40, 50, 60));
  printf("ack %ld %ld\n", ack(2, 3), ack(3, 3));
  return 0;
}
