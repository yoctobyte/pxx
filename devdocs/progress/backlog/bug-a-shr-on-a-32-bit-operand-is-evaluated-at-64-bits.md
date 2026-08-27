---
slug: bug-a-shr-on-a-32-bit-operand-is-evaluated-at-64-bits
title: "`shr` on a 32-bit operand is evaluated at 64 bits — `i shr 1` for i = -8 gives 9223372036854775804, FPC gives 2147483644"
track: A
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-28
summary: "Pascal's shr is a LOGICAL shift at the operand's own width. pxx performs it at 64 bits regardless of the operand's declared type, so a negative Integer shifted right yields a 63-bit value instead of a 32-bit one. Writing it back to an Integer then truncates to a third answer, so the same expression gives two different wrong results depending on whether it is stored."
---

# Repro

```pascal
program ShrProbe;
var i: Integer;
begin
  i := -8;
  writeln(i shr 1);            { A }
  writeln((-8) shr 1);         { B — untyped constant, genuinely 64-bit }
  i := -8; i := i shr 1; writeln(i);   { C }
end.
```

| | fpc 3.2.2 | pxx x86-64 |
| --- | --- | --- |
| A `i shr 1`, i: Integer | 2147483644 | **9223372036854775804** |
| B `(-8) shr 1`, untyped constant | 9223372036854775804 | 9223372036854775804 |
| C `i := i shr 1` | 2147483644 | **-4** |

B agreeing is the control: for an untyped constant the 64-bit answer is
correct, and pxx gets it right, so the shift itself is fine. A and C are the
same expression on a declared `Integer`, and they disagree with FPC *and with
each other* — C is A truncated to 32 bits by the store (0xFFFFFFFC = -4).

# Why it matters

`shr` on a signed value is not exotic — it is how hash mixers, bit-packing and
checksum code are written, and every such loop over a negative or high-bit-set
Integer silently produces a different number than FPC does. Nothing warns. Per
CLAUDE.md's compat table this is the silent-wrong-behaviour escape: real Pascal
source compiles and runs wrong, so it is a bug in its lane, not a compat item.

# The rule being missed

Pascal's `shr` is a **logical** shift performed at the width of the left
operand's type. There is no arithmetic right-shift operator in the language to
confuse it with. So the operand needs zero-extension to its declared width
before the shift, or the shift needs to happen at that width.

Note that C's `i := i shr 1` case shows the two halves are independently
wrong-ish: the store truncates correctly, the shift does not narrow first. Fix
the shift; do not "fix" it by relying on the store, because A has no store.

# Found

By the wasm32 backend, 2026-08-28, while building the Phase 2 differential.
wasm has separate `i32.shr_u` and `i64.shr_u` instructions and no implicit
promotion, so the backend has to choose a width and chose the operand's — which
made it disagree with the native build and agree with FPC. Same root shape as
[[bug-a-function-result-assignment-does-not-narrow-to-the-result-type]]: a
value's declared width is not enforced where a 64-bit register makes enforcing
it optional.

Blast radius beyond the lane: `test/wasm/phase2_slice.pas` keeps its shift
operands non-negative so the lane's gate does not go red for this. Above zero
the two widths agree; the coverage of the instruction is real, the coverage of
the semantics is not, and it cannot be until this closes.
