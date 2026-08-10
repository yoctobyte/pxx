---
track: U
prio: 40
type: decision
blocked-by: []
---

# Decide: should the operator-overload table be keyed on BOTH operand types?

- **Type:** decision (Track U) — a data-structure change with a miscompile
  hazard on the wrong choice.
- **Raised by** [[bug-a-a-mixed-type-record-operator-signature-fails-to-parse]],
  which fixed the reachable half and stopped at this fork rather than guessing.

## Where things stand (measured 2026-08-10)

`OvrlOpKind / OvrlTypeKind / OvrlRecId -> OvrlProcIdx` is keyed on **one**
operand type, and every use site looks up by the **LEFT** operand
(`parser.inc` x2, `ir.inc` x1). Today:

- `TVec * Integer` — works (keyed on TVec; right operand now disambiguated at
  lookup time by `FindOpOverload2`, which reads the proc's own params).
- `Integer * TVec` — **refused** at the definition:
  `impossible operator overload: this operation is predefined for built-in
  operand types`. FPC accepts it, and `3 * a` is ordinary code.

## Why the refusal is currently the SAFE answer

The guard rejects it because the pre-scan sees only the left operand's type
(`Integer`, `recId = REC_NONE`). But relaxing just the guard is **not** enough
and would be actively dangerous: with the table keyed on the left type, a
scalar-left operator registers under `(tkStar, tyInteger, REC_NONE)` — and since
the lookup consults the left operand, **plain `3 * 5` would match it** and be
miscompiled into a call to `TVec.*`. A wrong refusal would become a silent
wrong value in arithmetic that has nothing to do with the record.

## Options

1. **Key the table on both operand types.** `OvrlTypeKind2` / `OvrlRecId2`, and
   the three binary use sites pass the right operand. Correct and complete;
   `Integer * TVec` then registers unambiguously and `3 * 5` cannot match.
   Cost: a table column, three call sites, and a decision about what the unary /
   conversion operators (which have one operand) store in the second key.
2. **Keep one key, require the LEFT operand to be a record/class.** i.e. bless
   today's behaviour and keep refusing `Integer * TVec` forever, with a
   diagnostic that says *why* ("put the record on the left"). Zero risk, and a
   real dialect divergence from FPC.
3. **Keep one key, but key on whichever operand is the USER type**, and have
   the lookup try both operands. Avoids the table change; makes lookup
   order-sensitive and is the option most likely to grow a fourth special case
   later — the shape this repo keeps paying for.

## Recommendation

**Option 1.** The table is tiny and entirely private to `RegisterOpOverload` /
`FindOpOverload*`, the three use sites already have the right operand node in
hand (they were just changed to pass it), and it is the only option that makes
the dangerous case *impossible* rather than *refused*. Option 2 is the
acceptable fallback if the second key turns out to be awkward for the unary and
conversion operators — but it should then be a stated dialect rule, not an
accident of the lookup key.

Whichever way: `Integer * TVec` must not become reachable while the table is
keyed on one operand.
