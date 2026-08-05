/* Regression: a bare pointer DIFFERENCE passed to a variadic function must be
   pushed at ptrdiff_t width. The lowering hardcoded tyInt64, so on ILP32 the
   node claimed 8 bytes for a 4-byte value and every LATER argument read one
   slot low: printf("%d %d", t-s, 7) produced "3 0".

   The first value still came out right, which made it look like a library bug --
   strchr/strstr/memchr all appeared to "return wrong pointers" when the fault
   was in the caller's printf. Invisible on 64-bit, where an 8-byte push happens
   to be correct, and harmless in the LAST argument position, so a passing case
   proves nothing about its neighbour.

   Checked through sprintf (a real variadic call) rather than by eyeballing
   stdout, so the exit code carries the verdict.
   bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit */
#include <stdio.h>
#include <string.h>
#include <stddef.h>

struct Big { double a, b, c; };

int main(void) {
  char buf[128];
  const char *s = "abcdef";  const char *t = s + 3;
  int arr[10];               int *ip = arr + 7;
  struct Big bs[4];          struct Big *bp = bs + 3;

  sprintf(buf, "%d %d %d", t - s, 7, 8);            /* stride 1, two after */
  if (strcmp(buf, "3 7 8") != 0) return 1;
  sprintf(buf, "%d %d", s - t, 7);                  /* negative            */
  if (strcmp(buf, "-3 7") != 0) return 2;
  sprintf(buf, "%d %d", ip - arr, 7);               /* stride 4            */
  if (strcmp(buf, "7 7") != 0) return 3;
  sprintf(buf, "%d %d", bp - bs, 7);                /* stride 24           */
  if (strcmp(buf, "3 7") != 0) return 4;
  sprintf(buf, "%d %d %d", t - s, ip - arr, bp - bs);
  if (strcmp(buf, "3 7 3") != 0) return 5;
  sprintf(buf, "%d %d", 7, t - s);                  /* last position       */
  if (strcmp(buf, "7 3") != 0) return 6;
  sprintf(buf, "%d", (int)(t - s));                 /* explicit cast       */
  if (strcmp(buf, "3") != 0) return 7;
  /* ptrdiff_t is pointer-width, not always 8 */
  if (sizeof(t - s) != sizeof(void *)) return 8;
  return 42;
}
