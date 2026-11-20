---
summary: "RESOLVED 2026-11-20: riscv32 narrows a 64-bit compare to 32 bits when both sides are exactly 32-bit (Rv32Exact32). For a constant it tested the SIGNED range of IRIVal, but an unsigned 64-bit constant stores its bit pattern there: 18446744073709551613UL is -3. So `18446744073709551613UL < 0` was TRUE and `> 5` was FALSE. csmith seed 1130101 (riscv32 only; gcc and the other four targets agree) exited a nested loop early. A uint64 constant with the top bit set is now not exact. Xtensa's twin (XtExact32) got the same guard; it did not reproduce there, so that half is defensive."
type: bug
track: R
prio: 75
status: done
created: 2026-11-20
found-by: claude-dupwt (csmith sitting, seeds 1130000..1130149, riscv32)
owner: claude-dupwt
tags: [codegen, riscv32, xtensa, esp, csmith]
blocked-by: []
---

## Symptom

csmith seed 1130101 on `--target=riscv32` gave checksum 838A80B0 at -O0 and
-O2. gcc (-m32 and LP64), plus pxx on i386, arm32, x86-64 and aarch64, all give
81C2ABD7. The program is clean under gcc -Werror=uninitialized, MSan and UBSan.
cvise, with those guards, plus hand reduction, came down to:

```c
int a = 18446744073709551613UL < 0;   /* riscv32: 1, gcc: 0 */
int d = 18446744073709551613UL > 5;   /* riscv32: 0, gcc: 1 */
```

A `volatile unsigned long long` holding the same value compared correctly, and
so did an explicit cast. Only the bare constant failed.

## Cause

The IR is the same on i386 and riscv32: `const_int ival=-3 tk=UInt64` against
`const_int 5`. The riscv32 binop arm skips the ~10-instruction pair compare
when `Rv32Exact32` says both sides are reproduced by extending a 32-bit
register. Its constant arm checked `-2^31 <= v <= 2^31-1` on IRIVal, which for
an unsigned 64-bit type is the bit pattern. 2^64-3 passed as -3, and the
compare ran signed in 32 bits.

## Fix

`Rv32Exact32` (compiler/ir_codegen_riscv32.inc) now returns False for a
constant whose type is an 8-byte unsigned integer and whose pattern is
negative. `XtExact32` (compiler/ir_codegen_xtensa.inc) got the same guard. On
Xtensa the test matched gcc before the fix as well, so that path was not
reached here; the guard keeps the twins identical.

## Test

`test/c_uint64_constant_above_2_63_compares_unsigned.c` has 14 compares of
constants at or above 2^63, against constants, an int and an unsigned, in both
operand orders. The expected output is gcc -m32's.

| row | target | where |
|---|---|---|
| riscv32/u64cmp, riscv32/u64cmp2 | riscv32, -O0 and -O2 | test-riscv32 |
| xtensa/c_xtu64cmp | xtensa posix, call0, -O2 | beside c_xtasm |

The latest compiler before the fix gets 3 lines wrong on riscv32. After the
fix, riscv32, xtensa and i386 all match gcc. Seed 1130101 now prints
81C2ABD7.
