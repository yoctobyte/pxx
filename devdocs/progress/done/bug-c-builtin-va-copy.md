---
prio: 50
---
# C: __builtin_va_copy not supported (blocks tcc libtcc.c)

- **Type:** bug (cfront — missing GCC builtin). Track C.
- **Found:** 2026-07-07, tcc bring-up (first blocker in libtcc.c).

## Symptom
`libtcc.c:10545: call to undeclared function: __builtin_va_copy`. pxx handles
`__builtin_va_start` / `__builtin_va_arg` / `__builtin_va_end` (ParseCPrimary,
cparser.inc ~437–522) but not `__builtin_va_copy(dest, src)`, which duplicates a
va_list's traversal state (C99 7.15). Common in libraries that fan a va_list out
to more than one consumer.

## Fix site + approach
Add a branch in ParseCPrimary next to the other `__builtin_va_*` handlers.
va_copy(dest, src) copies the va_list contents from src to dest. pxx models
va_list as an array/record (see CVaListAddr + `__va_save` tyRecord in va_start);
so lower to a byte/record copy of the va_list from `CVaListAddr(src)` to
`CVaListAddr(dest)` (size = the va_list record size, 24 on x86-64 SysV: gp_offset,
fp_offset, overflow_arg_area, reg_save_area). Mirror however va_arg reads the same
struct so the copied state stays consistent. Add a regression (two va_arg walks of
the same args via a copied list) + verify vs gcc.

## Gate
`__builtin_va_copy` compiles; tcc libtcc.c parse advances past :10545 to surface
the next blocker. Regression test green; self-host byte-identical.


## RESOLVED 2026-07-07 (Track A+C, sole-A)
Added a `__builtin_va_copy(dest, src)` branch in ParseCPrimary next to va_end.
va_list is `__pxx_va_elem[1]` (24-byte control block), so lower to a record copy:
build AN_ASSIGN of two record-typed AN_DEREFs over CVaListAddr(dest)/CVaListAddr(src)
(carrying the elem rec via ASTIVal), which the record path emits as IR_COPY_REC.
Regression b178 (two va_arg walks of the same args through a copied list → each
sees 1,2,3). tcc libtcc.c parse advances past :10545. self-host byte-identical;
c-conformance 198/0.
