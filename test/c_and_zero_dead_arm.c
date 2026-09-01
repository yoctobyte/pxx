/* `x & 0` is a constant-false branch condition, and busybox writes it as its
   feature-flag idiom:

       OPT_h = (1 << OPTBIT_h) * ENABLE_FEATURE_HUMAN_READABLE,   /- = 0 -/
       if (opt & OPT_h) column += printf(..., make_human_readable_str(...));

   With the feature off the mask is a literal 0, the arm is dead, and
   human_readable.c is not in the build. gcc emits no reference; pxx emitted
   one, and coreutils/ls.c was the ONLY undefined symbol left when all 49
   busybox translation units were compiled separately.

   So the arm must be ELIMINATED, not merely not-taken: `never_defined_anywhere`
   is declared here and defined NOWHERE, so this file LINKING AND STARTING AT
   ALL is half of what it asserts. Before the fix it died with
   `symbol lookup error: undefined symbol: never_defined_anywhere`.
   feature-c-corpus-busybox-multi-applet */
#include <stdio.h>

extern int never_defined_anywhere(int);

static int calls;
static int sideeffect(void) { calls++; return 7; }

/* busybox's own spelling: the mask is an ENUM CONSTANT the frontend has
   already reduced to a literal by the time the branch sees it. */
enum { ENABLE_IT = 0, OPTBIT_h = 3, OPT_h = (1 << OPTBIT_h) * ENABLE_IT };

int main(void) {
  int x = 5;
  int opt = 255;                 /* every bit set: the mask decides, not the value */

  printf("1 %d\n", (x & 0) ? never_defined_anywhere(1) : 11);
  printf("2 %d\n", (0 & x) ? never_defined_anywhere(2) : 22);   /* zero on the LEFT */

  if (opt & OPT_h) printf("NOTREACHED %d\n", never_defined_anywhere(3));
  printf("3 %d\n", OPT_h);       /* ls.c's shape, and the reason this test exists */

  /* THE ROW THAT CAUGHT THE FIRST CUT OF THE FIX. Folding the CONDITION must
     not delete the OPERAND: once the jump stops reading it, the binop has no
     live consumer and the call feeding it is collected too. The first version
     of this fold did exactly that and every "the arm is gone" row above still
     passed. gcc -O0, gcc -O2 and the pinned pxx all say 1.
     `sideeffect()` is impure, so the branch is deliberately NOT folded here --
     which is why this arm must not contain never_defined_anywhere: it would
     be a live reference, correctly. */
  if (sideeffect() & 0) printf("NOTREACHED impure\n");
  printf("4 %d\n", calls);

  /* The other direction -- a nonzero mask must stay a REAL branch, or the
     "fix" is just "never take the arm". */
  printf("5 %d\n", (x & 4) ? 55 : 0);
  printf("6 %d\n", (x & 2) ? 0 : 66);

  /* if(0) folded before this change too; the control that says which half was
     actually missing. */
  if (0) printf("NOTREACHED %d\n", never_defined_anywhere(5));
  printf("7 ok\n");
  return 0;
}
