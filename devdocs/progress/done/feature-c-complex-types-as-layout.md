---
slug: feature-c-complex-types-as-layout
track: C
prio: 55
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (libffi 3.5.2's src/types.c in Panorama's all-pxx dependency set)
tags: [cfront, crtl, libffi, panorama]
summary: "pxx did not know `_Complex` (`undeclared identifier '_Complex' used as value` in libffi's types.c, which records sizeof and offsetof of _Complex float/double/long double for ffi_type_complex_*). Now `_Complex T` (either order, and gcc's __complex__) is struct __pxx_complex_T { T __re, __im; } from crtl's pxx/complex_types.h, pulled in at the first mention as stdarg.h is for __builtin_va_list. Size, alignment, members, copies, and passing/returning by value match gcc (the SysV ABI passes these exactly as the structs), and an initialiser treats it as one scalar. Complex ARITHMETIC is not modelled and is refused by name (bug-c-struct-operands-to-scalar-operators-compile-silently). Tests c_cxlayout26, c_structop26_ref."
---

# `_Complex` as layout

libffi describes C's complex types to its callers:

```c
#define FFI_COMPLEX_TYPEDEF(name, type, maybe_const)
struct struct_align_complex_##name { char c; _Complex type x; };
... sizeof(_Complex type), offsetof(struct struct_align_complex_##name, x) ...
```

pxx had no `_Complex` at all. Full complex arithmetic (C99 Annex G,
`__real__`/`__imag__`, `I`, <complex.h>) is a large feature that nothing
in Panorama's dependency set needs: wayland passes no complex values
through libffi. Layout is what is needed, and layout can be done exactly:

- C11 6.2.5p13: a complex type has "the same representation and alignment
  requirements as an array type containing exactly two elements of the
  corresponding real type", which is also `struct { T re, im; }`.
- The SysV x86-64 ABI classifies `_Complex float` as one SSE eightbyte and
  `_Complex double` as two, the same as those structs, so by-value
  passing and returning agree with gcc.

What was done:

- `lib/crtl/include/pxx/complex_types.h`: the three structs.
- cpreproc: `CPMaybePullComplexTypes` includes that header the first time
  an expanded line mentions `_Complex`/`__complex`, as for va_list.
- cparser: `CIsComplexWord` makes `_Complex`/`__complex__`/`__complex` a
  type word (also for casts and sizeof). In ParseCDeclType it resolves after
  the loop to the struct tag (a bare `_Complex` is double, as gcc's
  extension). An integer complex (gcc extension) is refused by name.
- Initialisers: a complex member or array element given an unbraced value
  takes exactly one value, as its real part (C converts real to complex
  that way), instead of brace-eliding into `__re` and `__im`. Without this,
  `struct { int t; _Complex double z; float f; } s = { 7, 0, 1.0f };`
  put the 1.0f into z and left f 0.

Not modelled, refused by name: every operator, condition, cast and
scalar assignment on a complex value (see
bug-c-struct-operands-to-scalar-operators-compile-silently, which found
that pxx accepted those on any struct). `_Complex long double` inherits
pxx's 8-byte long double, which has its own ticket.

Tests: test/c_complex_layout.c (c_cxlayout26) against gcc; the complex
cases 9–13 of test/c_struct_operand_refused.c (c_structop26_ref).
libffi 3.5.2: 8/8 C units after (7/8 before).
