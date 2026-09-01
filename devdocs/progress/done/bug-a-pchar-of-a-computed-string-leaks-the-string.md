---
type: bug
track: A
prio: 5
summary: PChar(expr) over a computed AnsiString leaked the string — PXXPCharOf takes a Pointer, so no arg-temp site parked the operand
owner: frankB
---

## What

`PChar(someComputedString)` handed the callee a char pointer into a heap block
carrying a +1 that belonged to nobody. `TakeP(PChar('lit' + c))` leaked 937
blocks in 1000 trips; `TakeP(PChar(t))` against a named local was clean at 3,
because the local owned it.

## Why the seven arg-temp sites did not catch it

The PChar cast over a managed string routes through `PXXPCharOf`, the wrapper
that makes `PChar('')` a valid pointer to a shared `#0` byte instead of nil. It
is declared `function PXXPCharOf(p: Pointer): Pointer` — deliberately, it does
pointer arithmetic — so `ParamWantsManagedStrTemp` is False for it and none of
the seven managed-string-temp sites materialise anything at that call. The
operand's +1 was dropped on the floor, and no scope-exit scan could ever find
it: it was never a symbol.

Third instance of one shape, after `88e1ab536` (Variant→AnsiString) and
`f42665459` (an `array of const` element): **a lowering hands a fresh managed
string to a consumer that stores a raw pointer.** Fixed the same way and for the
same reason — at the seam that creates the value, unconditionally over
tyAnsiString, letting `IR_STORE_SYM` decide ownership via
`IRNodeOwnsFreshCallResult` rather than re-asking what SHAPE the operand had.

## Measured

Against `e7fb90cccb94`, the binary immediately before the fix:

| arm | before | after | allocs |
| --- | --- | --- | --- |
| `TakeP(PChar('lit' + c))` | 937 | 4 | 1871 |
| `TakeP(PChar(t))`, t a named local | 3 | 3 | 921 |

`test/test_pchar_of_computed_string_leaks.pas`: **1421 → 9** against a bound of
50, allocs 4809 either way — same traffic, so the delta is ownership. Rejected
by the pre-fix binary (rc=1), which is the check that says it can fail at all.
Identical numbers on x86-64/i386/aarch64/arm32/riscv32.

The lifetime created is scope exit, strictly LONGER than FPC's guarantee for
PChar-of-a-temporary (end of statement), so no program correct under the oracle
becomes wrong. `PChar('')` and `PChar(e + '')` both stay non-nil pointing at a
`#0`, checked by value in the test and matching FPC on every printed line.

## Log

- 2026-09-01 — found by sweeping sibling ownership seams after the array-of-const
  fix, fixed and closed in the same session, commit PENDING-COMMIT.
