---
track: C
tags: [cfront, varargs, rump, netbsd, nostdinc]
prio: 55
type: bug
blocked-by: []
summary: "`__builtin_va_list` (NetBSD sys/ansi.h: `typedef __builtin_va_list __va_list;`) was an undeclared identifier: pxx's va_list and the __pxx_va_* helpers live in crtl's <stdarg.h>, which such a unit never includes, and -nostdinc hides. Separately, under --system-libs every variadic DEFINITION failed even with <stdarg.h> included, because the helpers' stdarg.c was treated as a system-library header and not pulled. rump-pxx g09, g22."
status: done
owner: pxx2
---

# __builtin_va_list without a header

- cpreproc.inc CPMaybePullBuiltinVaList: the first live line mentioning
  `__builtin_va_list` pulls pxx's <stdarg.h> in above itself, by absolute path
  (CPCrtlHeaderAbs; /proc/self/cwd when the compiler path is relative). Once
  per unit; never once PXX_CRTL_STDARG_H is defined.
- stdarg.h: `typedef va_list __builtin_va_list;`.
- pasparser_proc.inc CHeaderUsesSystemLib: `stdarg` is compiler support, never
  a system library, so --system-libs still pulls stdarg.c.
- stdarg.c includes its header as "../include/stdarg.h" (-nostdinc units).

Test: test/c_builtin_va_list.c against gcc (x86-64, i386, and run from a
directory other than the repo). g22's object carries the helpers as WEAK
definitions, each in its own section.
