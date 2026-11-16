---
slug: bug-c-gcc-predefined-type-macros-and-pragma-operator-missing
track: C
prio: 70
type: bug
status: done
created: 2026-11-16
found-by: pxx (Gibux seat), rump-pxx g01 and g02 -- the two that block the most NetBSD files
tags: [cfront, preprocessor, rump]
blocked-by: []
summary: "Hosted x86-64 and i386 lacked gcc's integer-type predefines (__SIZE_TYPE__, __PTRDIFF_TYPE__, __INT64_TYPE__, *_MAX__, *_C(c), *_WIDTH__ ...) and __ELF__, so NetBSD's sys/common_ansi.h hit its #error and sys/cdefs.h picked cdefs_aout.h. Both sets are now measured from gcc -dM -E (and -m32), like the existing ESP/newlib block; __ELF__ is defined on every target but wasm. The C99 _Pragma operator reached the parser as a stray identifier (NetBSD's __BEGIN_PUBLIC_DECLS is _Pragma(\"GCC visibility push(default)\")): the preprocessor's emit path now destringizes it and runs it as #pragma at that output position, so _Pragma(\"pack(push,1)\") and push_macro/pop_macro work; text inside string literals is left alone. Visibility pragmas are accepted and ignored (s09 is separate). Test: c_ppop (test/c_predef_pragma_op.c; expected = gcc's output; i386 checked by hand)."
---
