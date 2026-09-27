---
track: C
prio: 50
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "On arm32 and riscv32, once the named parameters of a variadic function spill past the argument registers, va_arg reads the named words again instead of the variadic tail: the va_start seed capped the named bytes at the register area. arm32 also skipped AAPCS's 8-byte pad before a named double or long long. test/cvararg_stack_spill.c printed garbage on both. SILENT, same on v445."
---

# A variadic tail after stack-passed named params reads the named words

`int f3(int a, int b, int c, int d, int e, int n, ...)` on arm32 (r0-r3) and
nine named ints on riscv32 (a0-a7): va_arg returned `e`, `n`, ... .

Found by the cross-target differential, 2026-09-27 (cvararg_stack_spill,
c_wasm32_variadic on arm32).

## Resolution (2026-09-28)

`__builtin_va_start` (compiler/cparser.inc) no longer caps the named byte
count at the register area, and pads it to 8 before a named 8-byte value on
arm32; `__pxx_va_start_impl32` (lib/crtl/src/stdarg.c) starts the overflow
area past the named bytes that spilled. Fixture
`test/c_a_variadic_tail_after_stack_passed_named_params.c`: v445 arm32 5 rows
wrong, riscv32 1; this build none on all five targets.
