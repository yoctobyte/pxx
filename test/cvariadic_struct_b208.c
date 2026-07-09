/* Regression: passing a struct BY VALUE through `...` and reading it back with
   va_arg(ap, struct T). The C caller ABI marshals a by-value struct arg as a
   POINTER to a private copy (one GP/word slot), so va_arg(struct) must deref
   twice: load the pointer out of the slot, then read the record it points at.
   Before the fix it derefed the slot ADDRESS as a record and read pointer bits
   as struct data (garbage). bug-c-abi-battery-00204. */
#include <stdarg.h>
extern int printf(const char *, ...);

struct FF { float x, y; };        /* 8 bytes, one slot  */
struct S9 { char s[9]; };         /* 9 bytes, still one pointer slot */
struct Big { int a, b, c, d, e; };/* 20 bytes */
struct One { char c; };

static int ok = 0;

static void vp(int n, ...) {
  va_list ap;
  va_start(ap, n);
  int i0 = va_arg(ap, int);
  struct FF f = va_arg(ap, struct FF);
  struct S9 c = va_arg(ap, struct S9);
  struct Big b = va_arg(ap, struct Big);
  struct One o = va_arg(ap, struct One);
  int i1 = va_arg(ap, int);
  va_end(ap);

  if (i0 == 7 && f.x == 1.5f && f.y == 2.5f &&
      c.s[0] == 'A' && c.s[7] == 'H' && c.s[8] == 0 &&
      b.a == 10 && b.b == 20 && b.c == 30 && b.d == 40 && b.e == 50 &&
      o.c == 'Z' && i1 == 99)
    ok = 1;
  printf("i0=%d f=%.1f,%.1f s=%s big=%d,%d,%d,%d,%d one=%c i1=%d\n",
         i0, f.x, f.y, c.s, b.a, b.b, b.c, b.d, b.e, o.c, i1);
}

int main(void) {
  struct FF f = {1.5f, 2.5f};
  struct S9 c = {"ABCDEFGH"};
  struct Big b = {10, 20, 30, 40, 50};
  struct One o = {'Z'};
  vp(0, 7, f, c, b, o, 99);
  return ok ? 42 : 1;
}
