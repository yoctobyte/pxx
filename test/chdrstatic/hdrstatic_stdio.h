/* The SAME two bodied statics as hdrstatic.h, above a header that pulls a crtl
 * `.c` implementation. This file exists because hdrstatic.h deliberately does
 * NOT: its own comment records that <stddef.h> was chosen over <stdio.h>
 * because stdio pulls an impl, which put every following token inside that
 * module for CModuleOfTok's purposes, and the header-static fix declines to
 * compile bodies there.
 *
 * That residual was bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull
 * (Track A, resolved 8ba3425d1). This row is what keeps it closed: the fix
 * lives in a different lane's file, so nothing in the C tests would notice it
 * regressing, and the ONE header the existing test uses is the one shape that
 * never exercised it.
 *
 * The pair invariant is unchanged -- 4242 then 42, and no DT_NEEDED on a
 * lib<stem>.so that cannot exist. The soname assertion is the load-bearing
 * half: the values can be right while the binary is dead at load. */
#include <stdio.h>

static int hs_plain(void) { return 4242; }

static inline int hs_inline(int v) { return v + 1; }
