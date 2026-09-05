#include "macro_soup_defs.h"

/* G_GNUC annotations which should be ignored */
#define G_GNUC_PRINTF(a, b) __attribute__((__format__(__printf__, a, b)))
#define G_GNUC_MALLOC __attribute__((__malloc__))

/* Nested and recursive macro rescanning test */
#define INNER_ADD(a, b) ((a) + (b))
#define MID_ADD(a, b) INNER_ADD(a, b)
#define NESTED_ADD(a, b) MID_ADD(a, b)

/* Self-referential macro test (should not cause compiler crash/infinite loop).

   THE NAME IS DECLARED, and that is the whole of the fixture now. C 6.10.3.4/2
   blue-paints a macro during its own rescan, so `SELF_REF_MACRO' expands ONCE
   to `SELF_REF_MACRO + 1' and the inner occurrence stays the OBJECT below --
   which is why the rescan terminates and why gcc accepts this.

   It used to have no declaration at all, and leaned on the frontend folding the
   leftover token to 0 with a warning. That leniency is gone
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error),
   and removing it IMPROVED this test rather than costing it: "does not hang"
   was the only thing the old shape could assert, because the value it produced
   was the compiler's own stand-in. With the object declared there is an ORACLE
   -- pxx and `gcc -std=gnu99' both give `dummy' the value 7 -- so termination
   and correctness are now one assertion instead of half of one. */
static int SELF_REF_MACRO = 6;
#define SELF_REF_MACRO SELF_REF_MACRO + 1

/* defined without parentheses should work correctly */
#if defined MACRO_SOUP_DEFS_H
G_GNUC_MALLOC MS_API G_GNUC_PRINTF(1, 2) soup_add(int a, int b) {
    int dummy = SELF_REF_MACRO;
    return NESTED_ADD(a, b);
}
#else
int soup_add(int a, int b) {
    return 0;
}
#endif
