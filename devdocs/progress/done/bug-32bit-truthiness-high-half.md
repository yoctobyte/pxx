---
prio: 70
---

# `if (v)` on a 64-bit value tested only the LOW half on every 32-bit target

- **Type:** bug (correctness — silent wrong control flow, no diagnostic)
- **Track:** A — backends (i386 / arm32 / riscv32)
- **Status:** done — fixed 2026-07-12, commit 3368863b.
- **Found by:** chasing a crtl printf failure in c-testsuite 00204 (i386).

## Symptom
A 64-bit value lives in a register PAIR on ILP32, but `IR_JUMP_IF_FALSE` tested only
the low half:

| target | emitted | ignores |
| --- | --- | --- |
| i386 | `test eax, eax` | edx |
| arm32 | `cmp r0, #0` | r1 |
| riscv32 | `bne a0, zero` | a1 |

So any nonzero value whose low 32 bits happen to be zero — `0xabcd00000000` — was
branched on as **false**. `if (v)`, `while (v)`, `(v) ? :` and short-circuit operands
all lower to that op.

An EXPLICIT `v != 0` compiles to a real 64-bit compare and was always correct. That
is exactly what hid the bug: the idiomatic spelling was broken, the pedantic one was
not.

## Fix
Fold the halves before the test, so the zero flag reflects the whole value:
`or eax, edx` / `orrs r0, r0, r1` / `or a0, a0, a1`. arm32 emits the raw word for
`orrs` — the text emitter only knows `orr`, and the backend already spells this
instruction as a literal encoding elsewhere.

## How it surfaced
crtl's `__crtl_utoa` does `while (v)`. Once printf was fixed to actually read 64 bits
(see [[bug-crtl-printf-ll-ilp32]]), that loop exited immediately on `0xabcd00000000`
and `%llx` printed NOTHING — which pointed straight at the truthiness test.

## Regression
`test/ctruthy_int64_b251.c`, run in `make test` as BOTH a 64-bit and a 32-bit binary.
The 32-bit run is the one that matters.

## Gate
make test + self-host byte-identical + `testmgr --tier full` (1199/1199).
