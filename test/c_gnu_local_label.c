/* GNU local labels, `__label__ name;` (NetBSD's rump sources reach them
   through macros that expand to a statement expression with its own label).
   Each expansion gets its own label, so one function can use the macro
   twice; a labelled last statement still gives the expression its value; an
   inner block's local label shadows an outer one of the same name; and
   `&&label` takes the local one. The output is gcc's. */
#include <stdio.h>

#define TWICE_OR(x) ({ __label__ out; int r_ = (x); if (r_ > 10) goto out; r_ *= 2; out: r_; })

static int two(int a, int b) { return TWICE_OR(a) + TWICE_OR(b); }

static int shadow(int n) {
  int r = 0;
  {
    __label__ skip;
    if (n > 0) goto skip;
    r += 1;
  skip:
    r += 10;
    {
      __label__ skip;
      if (n > 1) goto skip;
      r += 100;
    skip:
      r += 1000;
    }
  }
  return r;
}

static int viaaddr(int n) {
  return ({ __label__ a, b; void *t = n ? &&a : &&b; int v; goto *t;
            a: v = 1; goto done_; b: v = 2; done_: v; });
}

int main(void) {
  printf("%d %d %d\n", two(1, 2), two(20, 3), two(30, 40));
  printf("%d %d %d\n", shadow(0), shadow(1), shadow(2));
  printf("%d %d\n", viaaddr(1), viaaddr(0));
  return 0;
}
