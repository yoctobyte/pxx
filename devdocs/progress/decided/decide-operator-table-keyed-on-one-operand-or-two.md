---
track: U
prio: 40
type: decision
status: resolved
resolved: 2026-08-10
blocked-by: []
---


## DECIDED 2026-08-10 — key on BOTH operands. Single-keyed was an oversight.

**User's call.**

> "idk, i always assumed that would take both keys. the issue is more, we cannot
> just swap left and right, not even for multiply and addition. that may work for
> natural numbers, but not for a zillion other cases. [...] so yes, both keys,
> obviously. single keyed is an oversight of ours" — user

### That also settles why option 3 was wrong

Option 3 ("key on whichever operand is the user type, try both at lookup") is not
merely inelegant — it is **incorrect**, because trying both operands makes every
operator effectively commutative. `a - b` is not `b - a`; neither is `/`, matrix
multiply, or string concatenation. Commutativity holds for the naturals people
test with and fails for most of what operator overloading is actually FOR.
Rejected on correctness, not cost.

### Cheaper than this ticket originally stated

`FindOpOverload2` landed the same day (`7e45a9def`), so **all three binary use
sites already compute and pass the right operand** — `parser.inc` x2 and
`ir.inc` x1. The remaining work is the second key column in
`RegisterOpOverload` / the `Ovrl*` arrays and matching on it, not a plumbing
change.

### The one real design question: matching the SECOND key

Raised by the user, and both halves measured against `fpc -O1` — **both are
legal FPC**:

```pascal
class operator + (const a: TVec; const b: Variant): TVec;   { legal }
class operator + (const a: TR;   const b: TVarRec): TR;     { legal }
```

- **`TVarRec` is a non-issue.** It is an ordinary record; it matches by
  `RecName` exactly like any other record operand. No special case.
- **`Variant` IS the issue.** It is a wildcard. Declare
  `operator +(TVec, Variant)` and write `v + 3` — the right operand's STATIC
  type is `tyInteger`, not `tyVariant`, so **identity matching on the second key
  would fail to find the overload.**

So the second key must match by **compatibility with precedence**, not identity:

1. exact type match (and `RecName` match for record/class) — best;
2. a `Variant` parameter accepts any operand — fallback;
3. otherwise no match.

The precedence is load-bearing in both directions: without it, a `Variant`
overload registered first would shadow every specific one, and registered last
would never be reached.

### Strong recommendation on HOW

**Do not hand-roll a second ranking.** pxx already has overload ranking with
exactly these rules, entered through a single point —
`MatchCallDelphiProcAddr` is the one entry into `MatchProcCall*`, and per-argument
facts ride its side channel (`MatchArgRec` / `MatchQuiet` / `MatchExactOnly`)
rather than through `argTypes`. Route operator selection through that instead of
growing a parallel matcher, or the two will drift — which is the failure this
codebase keeps paying for.

### Also to decide while implementing

What the **unary and conversion** operators (`:=`, `Explicit`, `Inc`, `Dec`,
`Enumerator`) store in the second key. They have one operand. A reserved
"absent" value is the obvious answer; whatever it is, it must not collide with a
real `tyUnknown`.

### Payoff

`Integer * TVec` becomes registrable and the current refusal
(`impossible operator overload: this operation is predefined for built-in
operand types`) can go — while plain `3 * 5` becomes UNABLE to match a record
operator, rather than merely refused. That is the whole point: the dangerous case
stops existing instead of being guarded.


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

### Scope note (user, 2026-08-10) — the Variant case is PASCAL-only in practice

> "nilpy would first need to load a pascal library that uses operator
> overloads.. it's all a bit niche [...] python has it's own way of operator
> overloads, so we can sortof safely limit ourselves to pascal and assume python
> will call nicely statically defined functions that uses those operators."

NilPy does not use this table: its operators go through the dunder protocol
(`PyFindDunder`), not Pascal `class operator` registration. So a Variant or
promotable-int operand only reaches the second key when NilPy loads a PASCAL
unit that overloads operators — a real but niche path.

**Implement for Pascal operands first.** Get exact + record `RecName` matching
right, keep the `Variant`-accepts-anything fallback because FPC allows the
declaration, and do NOT build promotable-int or variant-payload ranking on
speculation. Revisit if a real NilPy-over-Pascal-operators case appears.
