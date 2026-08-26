---
track: U
prio: 30
type: decide
blocked-by: []
status: decided
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

---

# DECIDED 2026-08-25 — **option 2: 64-bit LOGICAL `shr` for Pascal, arithmetic for NilPy**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived** — and the
derivation is stronger than the ticket's own recommendation, because the fork is
not actually Pascal-versus-FPC. It is pxx versus itself.

## What was measured (pinned compiler, 2026-08-25)

The ticket compares the Variant path against FPC and never asks what pxx's own
STATIC path does. It does this:

| expression | fpc 3.2.2 `-Mobjfpc` | pxx (pinned) |
| --- | --- | --- |
| `Integer(-12) shr 1` | 2147483642 | **9223372036854775802** |
| `Int64(-12) shr 1` | 9223372036854775802 | **9223372036854775802** |
| `Variant(-12) shr 1` | 2147483642 | **-6** |

So pxx's static Pascal `shr` is already a **64-bit logical** shift, on both
widths. Its Variant `shr` is a 64-bit **arithmetic** shift. Those are two
different operators wearing one spelling, inside one language, in one compiler.

Note also that FPC's answers are not the "artifact" the ticket describes: FPC is
perfectly self-consistent (logical `shr` at the operand's declared width, and a
Variant small int is `varInteger`, i.e. 32-bit). The only party being
inconsistent with itself here is pxx.

## The principle

`normalise-dont-special-case.md`:

> *"When the frontend can reach a construct through **two shapes** — a constant
> and a variable, a literal receiver and a named one, **a static type and a
> variant** — it is tempting to give each its own path. Resist it."*

Static-versus-variant is the note's own third example, named explicitly. And its
table of five 2026-08-06 recurrences is entirely this shape. `shr` on a negative
Variant is the same bug the note was written about, caught before it cost
months.

So the answer is not "pick the nicer semantics" — it is "the Variant path owes
whatever the static path already commits to," which is the 64-bit logical shift.
That the result also matches Pascal's definition of `shr` is a consequence, not
the argument.

## Why not option 3 (narrow to 32 bits like FPC)

Two reasons, either sufficient. It would silently discard the top half of a
64-bit payload the user put there and can read back with `+` — a wrong answer
nobody chose. And it would newly *break* agreement with pxx's own static path,
which today already answers 64-bit.

FPC's 32-bit narrowing is a *behaviour*, not a bug (deterministic, derivable,
programs can depend on it), so by `meta-dialect-extensions-and-fpc-strict` its
correct home is the strict family — `--strict-fpc` may narrow a Variant integer
to `varInteger` before a bitwise op if a corpus ever needs it. Not the default.

## NilPy keeps the arithmetic shift

Python's `>>` sign-extends, so NilPy is right today and must not change. The
split is at the lowering seam that already exists for this purpose
(`PyProgramMode` selects the helper) — one arm, plus one `sar`→`shr` byte in the
x86-64 emitter. `the-substrate-is-ast-and-ir-not-the-parser.md`: *"Normalise
**within** a language, duplicate **across** languages."* Two languages, two
definitions of one token, one seam. Exactly the intended shape.

## Scope

The same answer settles the width and signedness of `and` / `or` / `xor` /
`shl` on a Variant: 64-bit, matching the static path in each case. The "not
covered" note in `test/test_variant_bitwise_and_not.pas` should be rewritten to
assert the static/variant agreement rather than to record its absence.

## Re-filed as work

Track **A**: `bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical`,
prio 50 — a genuine self-inconsistency producing a wrong value, not a parity
nicety, which is why it outranks its parent decision's 30.

## Log
- 2026-08-25 — decided, commit 28c19f214.
