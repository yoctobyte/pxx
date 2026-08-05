/* Regression: C99 6.3.1.2 — "When any scalar value is converted to _Bool, the
   result is 0 if the value compares equal to 0; otherwise the result is 1."
   That is a COMPARISON, not a truncation.

   _Bool was mapped straight to tyUInt8, so nothing downstream could tell it
   from `unsigned char` at the point of USE and every conversion was a
   truncating 1-byte store:
     _Bool b = 256;    stored 0   -- a TRUE value reading false
     _Bool ok = ptr;   kept the pointer's low byte -- 1 valid pointer in 256
                       reads as NULL, allocator-dependent, non-reproducing
     b == 1            false after b = 5
   Fixed by giving _Bool its own type kind (tyBool8, same 1-byte storage) and
   normalising at every conversion site the standard names: assignment, decl
   init, cast, argument passing and return.

   Note lib/crtl/include/stdbool.h does `#define bool int`, so <stdbool.h> code
   never hit this -- only source spelling _Bool directly, which is why it went
   unnoticed.
   bug-a-bool-conversion-does-not-normalise-to-0-or-1 */
#include <stdio.h>
#include <string.h>

_Bool ret_big(void)  { return 256; }          /* return conversion  */
_Bool ret_ptr(void)  { int x; return (void*)&x; }
static int take(_Bool b) { return (int)b; }   /* argument conversion */
struct S { _Bool f; };
_Bool g;                                       /* global              */

int main(void) {
  char buf[64];
  _Bool t = 5, z = 0, c = (_Bool)2;            /* init + cast         */
  int p = 42;
  _Bool fromptr = (_Bool)(void *)&p;

  if ((int)t != 1) return 1;
  if ((int)c != 1) return 2;
  if ((int)z != 0) return 3;
  if ((int)fromptr != 1) return 4;
  if (!(t == 1)) return 5;                     /* b == 1 after b = 5  */
  if (t == 5) return 6;

  { _Bool a[3]; a[0] = 7; a[1] = 0; a[2] = 256;
    if ((int)a[0] != 1 || (int)a[1] != 0 || (int)a[2] != 1) return 7; }
  { int n = 300; _Bool b2 = n; if ((int)b2 != 1) return 8; }

  if ((int)ret_big() != 1) return 9;
  if ((int)ret_ptr() != 1) return 10;
  if (take(256) != 1) return 11;
  if (take(0)   != 0) return 12;

  { struct S s; s.f = 256; if ((int)s.f != 1) return 13; }
  g = 512; if ((int)g != 1) return 14;
  { _Bool b = 0; b += 256; if ((int)b != 1) return 15; }
  { _Bool b = 0; b = !b;   if ((int)b != 1) return 16; }
  { _Bool d = 5; if ((int)(1 ? (_Bool)256 : d) != 1) return 17; }

  /* storage is still one byte, and a _Bool* cast must NOT normalise */
  if (sizeof(_Bool) != 1) return 18;
  { _Bool bb = 1; _Bool *bp = (_Bool *)&bb; if ((int)*bp != 1) return 19; }

  /* the conversion reaches a variadic call correctly too */
  sprintf(buf, "%d %d", (int)t, (int)z);
  if (strcmp(buf, "1 0") != 0) return 20;

  return 42;
}
