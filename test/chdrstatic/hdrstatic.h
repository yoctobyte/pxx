/* A `static` DEFINED in a header. The `uses <header>` path assumed a header
 * "declares and defines nothing", dropped the body, marked the function
 * external, and synthesised a soname from the header's own stem -- so calling
 * it produced a binary with a DT_NEEDED on lib<header>.so that cannot exist,
 * dead at load. `static` has INTERNAL linkage: there is no library to import
 * from, because the definition IS the header.
 *
 * The invariant this file exists to assert is the PAIR: the same source text
 * must behave the same whichever extension it is given (hdrstatic_c.c is the
 * identical two functions).
 *
 * The #include is deliberate, not incidental -- it proves an ordinary header
 * include does not defeat the fix. It is <stddef.h> and not <stdio.h> for a
 * reason recorded in the ticket: a header that pulls a crtl `.c` impl (stdio,
 * string, stdlib, math) puts the following tokens inside that module for
 * CModuleOfTok's purposes, and the fix declines to compile bodies there. That
 * residual is still open. */
#include <stddef.h>

static int hs_plain(void) { return 4242; }

static inline int hs_inline(int v) { return v + 1; }

/* Never called. Measured to be harmless before AND after: an uncalled bodied
   static produces no DT_NEEDED either way. Here so that stays true. */
static inline int hs_unused(int v) { return v * 3; }

/* The FFI surface: a bare declaration must keep its old treatment, i.e. still
   become an external import. Not called, so nothing needs to resolve it. */
int hs_declared_only(int v);
