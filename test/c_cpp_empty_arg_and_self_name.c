/* SPDX-License-Identifier: Zlib */
/*
 * Two preprocessor rules that busybox's xatonum_template.c is written entirely
 * in, and that this compiler got wrong in ways with NO diagnostic:
 *
 *  1. C99 6.10.3p4 -- `m()` on a macro that HAS parameters supplies ONE
 *     argument whose token sequence is EMPTY, not zero arguments. Read as
 *     zero, the sole parameter stays UNBOUND: `#define pfx(r) base##r`
 *     expanded `pfx()` to the literal identifier `baser`. A plausible name, so
 *     the DEFINITION simply went missing and the call went to the system libc.
 *
 *  2. C99 6.10.3.4p2 -- a macro whose expansion is its OWN name is not
 *     re-expanded, so it must not swallow the parameter list that follows it.
 *     `unsigned f()(const char *n)` spliced into `f(const char *n)` and came
 *     back out as `unsigned fconst char *n`: the declaration destroyed.
 *
 * Every row is a differential against a glibc-built binary of this same file.
 * The controls matter as much as the fixes: rows `cat`/`ind` are the legitimate
 * splice (the name came from PASTING, not from the macro itself), which the
 * 6.10.3.4p2 rule must NOT break.
 */
#include <stdio.h>

#define pfx(rest)  base##rest
#define sfx(rest)  rest##_tail
#define both(a, b) a##b

int pfx(_one)(void) { return 1; }
int pfx()(void)     { return 2; }   /* base ## <placemarker> -> base */
int sfx()(void)     { return 3; }   /* <placemarker> ## _tail -> _tail */
int both(, x)(void) { return 4; }
int both(y, )(void) { return 5; }

/* The self-referential shape, verbatim from xatonum_template.c's idiom. */
#define selfn(rest) selfn##rest
int selfn(_sfx)(int v) { return v + 10; }
int selfn()(int v)     { return selfn_sfx(v) + 100; }
/* Exactly what xatonum_template.c does at its tail: the macro is undefined
   once it has spelled the definitions, so callers use the plain name. */
#undef selfn

/* Control: the splice that MUST still happen. `ind()` expands to `tgt`, which
   is a different macro, so the following (…) belongs to it. */
#define tgt(a)     ((a) * 3)
#define ind(rest)  tgt##rest
#define cat(a, b)  a##b
#define ab(v)      ((v) + 7)

/* Zero-parameter macros are the boundary case the fix must not disturb: for
   `#define nul()`, `nul()` really IS zero arguments. */
#define nul() 42

int main(void)
{
  printf("%d %d %d %d %d\n", base_one(), base(), _tail(), x(), y());
  printf("selfn: %d %d\n", selfn(5), selfn_sfx(5));
  printf("splice: %d %d\n", ind()(4), cat(a, b)(1));
  printf("nul: %d\n", nul());
#if nul() == 42
  printf("if nul: yes\n");
#endif
#if pfx() != 0
  printf("if empty arg pasted a name, so it is 0 in #if: no\n");
#else
  printf("if empty arg: undefined identifier -> 0\n");
#endif
  return 0;
}
