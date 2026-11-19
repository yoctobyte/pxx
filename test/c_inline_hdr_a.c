/* The one external definition of `twice` (C99 6.7.4p7: an `extern`
   declaration in the translation unit that holds the inline definition).
   Linked with c_inline_hdr_b.c.
   bug-c-a-c99-inline-function-in-a-header-is-a-strong-symbol-in-every-object */
#include "c_inline_hdr.h"
extern inline int twice(int x);
int quad(int x) { return twice(twice(x)); }
