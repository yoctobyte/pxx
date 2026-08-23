---
track: U
prio: 30
type: decide
blocked-by: []
status: backlog
summary: "FPC narrows a Variant to 32 bits before a bitwise op, so `v(-12) shr 1` is 2147483642 there; pxx works in 64 bits and its `shr` is arithmetic, giving -6. Three readings of one expression (FPC's, Pascal's logical shr, our sar) and they agree on every non-negative operand. Which one do we owe?"
---

# What width — and what sign — does a Variant bitwise op have?

Raised 2026-08-24 out of [[bug-a-not-on-an-integer-variant-answers-a-boolean]],
which made the bitwise operators work on every target. They now agree with
`fpc 3.2.2 -Mobjfpc` on every non-negative operand. Negative operands have
three defensible answers and no obvious winner, so it is parked rather than
guessed.

```pascal
var a, c: Variant;
begin
  a := -12;
  c := a shr 1;   { fpc 2147483642   pxx -6 }
end.
```

- **FPC: 2147483642.** Its Variant integer promotes to `varInteger`, which is
  32-bit, so the operand becomes `Cardinal(-12) = 4294967284` and the logical
  shift halves it. This is an artifact of FPC's variant type ladder, not a
  statement about `shr`.
- **Pascal's own rule: 9223372036854775802.** `shr` on an ordinal is a LOGICAL
  shift, and our Variant payload is genuinely 64-bit.
- **What pxx does today: -6.** An arithmetic shift, because x86-64's inline
  `EmitVarBinOp` emits `sar` — chosen for NilPy, where Python's `>>`
  sign-extends — and the runtime twin was made to match it deliberately so the
  two implementations could not drift again.

## The fork

1. **Keep 64-bit arithmetic `shr`** (today). One rule for Pascal and NilPy,
   nothing to split at the lowering seam. Diverges from FPC on negative
   operands and from Pascal's own definition of `shr`.
2. **64-bit LOGICAL `shr` for Pascal, arithmetic for NilPy.** Correct by the
   language definition on both sides. Costs a split at the lowering seam that
   already exists (`PyProgramMode` selects the helper) plus one `sar`→`shr`
   byte in the x86-64 emitter — small, and the pattern is established.
3. **Narrow to 32 bits like FPC.** Byte-for-byte FPC parity, at the price of
   silently discarding the top half of a 64-bit Variant payload — a value the
   user put there and can read back with `+`. Reproduces an artifact rather
   than a rule.

**Recommendation: option 2.** It is the only one that is right by a
specification rather than by imitation or by inertia, it is what the `compat`
tag says a frontend owes its reference language (`shr` is defined by Pascal,
not by FPC's variant ladder), and the cost is a one-line split at a seam that
is already there for exactly this purpose. Option 3 loses information no
program asked us to lose.

Whatever is chosen, the same question settles the WIDTH of `and` / `or` /
`xor` / `shl` on a Variant, and the wording of the "not covered" note in
`test/test_variant_bitwise_and_not.pas`.
