---
slug: bug-c-setjmp-cannot-be-used-as-a-function-value
track: C
prio: 35
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, crtl, setjmp]
blocked-by: []
summary: "DONE 2026-11-22: `setjmp` was a macro only, so micropython's `(void *)setjmp` in its native-emitter table (py/nativeglue.c) was an undeclared identifier. The compiler now emits a real `setjmp` beside `__pxx_setjmp` (EmitCSetjmpStubs, the same body), and setjmp.h declares it. jmp_buf and sigjmp_buf became glibc's ARRAY OF ONE STRUCT: as a by-value struct, a function given a jmp_buf got a copy, and a setjmp through a pointer filled the copy. Test c_sjval26 (x86-64, i386, aarch64; arm32/riscv32 checked by hand). Residual: bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64."
---

# setjmp cannot be used as a function value

C 7.13 lets setjmp be a macro, but glibc's is also a function, and code takes
its address. micropython's native emitter keeps `setjmp` in `mp_fun_table`.

Two changes:

1. **A real setjmp.** EmitCSetjmpStubs runs its per-target body twice, once
   for `__pxx_setjmp` and once for `setjmp`. The bodies are byte-identical:
   setjmp must run in its caller's frame, so a C wrapper would not work.
   `<setjmp.h>` declares `extern int setjmp(jmp_buf env);` next to longjmp's
   declaration. The macro still wins wherever `setjmp(` is written.
2. **jmp_buf is `struct __jmp_buf_tag[1]`**, as in glibc (and sigjmp_buf is
   `struct __sigjmp_buf_tag[1]`). The plain struct dated from when an array
   typedef lost its dimension. That is fixed: sizeof, struct fields and
   parameters match gcc on x86-64, i386 and aarch64. A by-value struct
   parameter is a copy, so `int (*f)(jmp_buf) = setjmp; f(jb)` wrote into
   the copy and a later longjmp(jb) restored zeros. As an array, it decays
   to the caller's buffer. The macros now pass `env` instead of `&(env)`, and
   longjmp/_longjmp/siglongjmp in src/setjmp.c pass `env` on.

Test: test/c_setjmp_as_value.c covers a function table, a longjmp through a
pointer and through a `jmp_buf` parameter, a jmp_buf as a struct field, and
siglongjmp through a parameter. It matches gcc on all five targets (rows: x86-64,
i386, aarch64).

Not fixed: a setjmp *called* through a pointer and then longjmp'd to crashes on
x86-64 only. See bug-c-a-setjmp-called-through-a-pointer-cannot-be-returned-to-on-x86-64.
