# C: 6+ variadic args (overflow area) segfault

- **Type:** bug (Track A / shared codegen — variadic ABI overflow area).
- **Found:** 2026-06-26 finishing the crtl printf engine.

## Symptom
A variadic call with **6 or more variadic args** misreads the overflow-area
argument; 5 or fewer work.
```c
printf("%d %d %d %d %d\n", 1,2,3,4,5);     /* ok */
printf("%d %d %d %d %d %d\n", 1,2,3,4,5,6); /* wrong 6th arg */
```
All printf conversions (%d/%x/%s/%c/%p/%f/%e/%g + flags/width/prec) match gcc
for <=5 varargs; only the arg COUNT triggers it (values irrelevant).

## Cause (narrowed)
SysV passes the first 6 GP args in rdi..r9; a variadic callee like
`printf(fmt, ...)` has 1 named GP (fmt) + N varargs, so the **7th GP arg**
(= the 6th vararg) lands in the caller's stack overflow area, not a register.
The internal variadic call (ir_codegen.inc ~3039) pops only up to 6 args into
registers (`vaPopN > 6 -> 6`) and the register-save prologue saves rdi..r9; the
6th vararg sits in the overflow area. `__pxx_va_arg_gp` must switch from the
register-save area to `overflow_arg_area` once gp_offset passes 48, and that path
(or the overflow pointer the variadic prologue records) is wrong → deref of a bad
address.

Fix: make the variadic prologue record a correct `overflow_arg_area` pointer
(first stack vararg = [rbp+16] in the internal convention) and have
`__pxx_va_arg_gp` (stdarg.h / __pxx_va_* helpers) read from it when the GP
register-save area is exhausted. Verify with 6/7/8-arg printf == gcc.

## Impact
Low for now — lua's printf-family calls are typically <=5 args. Does not block
the libc-free stdio milestone (engine + <=5-vararg calls match gcc).

## Audit

- 2026-06-27 — Still open, but the symptom improved from segfault to wrong value.
  Current `compiler/pascal26` compiles/runs a six-vararg `printf`; it exits `42`
  and prints `1 2 3 4 5 4292415` instead of `1 2 3 4 5 6`.
