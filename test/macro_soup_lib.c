#include "macro_soup_defs.h"

/* G_GNUC annotations which should be ignored */
#define G_GNUC_PRINTF(a, b) __attribute__((__format__(__printf__, a, b)))
#define G_GNUC_MALLOC __attribute__((__malloc__))

/* Nested and recursive macro rescanning test */
#define INNER_ADD(a, b) ((a) + (b))
#define MID_ADD(a, b) INNER_ADD(a, b)
#define NESTED_ADD(a, b) MID_ADD(a, b)

/* Self-referential macro test (should not cause compiler crash/infinite loop) */
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
