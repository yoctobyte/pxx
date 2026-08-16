---
summary: "Implement the 2026-08-10 decision: key the operator-overload table on BOTH operand types. Until then `operator + (a: Double; b: TCx)` stays refused ('cannot determine operand type' / 'predefined for built-in operand types') where FPC accepts it. Relaxing only the guard would MISCOMPILE plain `3 * 5`."
type: feature
prio: 40
track: A
blocked-by: []
---

# Key the operator-overload table on both operands

- **Type:** feature (Pascal frontend + symtab) — Track A: `compiler/parser.inc`,
  `compiler/symtab.inc`, `compiler/ir.inc`.
- **Status:** backlog. **This is the re-filing of an already-DECIDED question**,
  not a new proposal.

## The decision is already made — do not re-open it

[[decide-operator-table-keyed-on-one-operand-or-two]], resolved **2026-08-10**:

> "idk, i always assumed that would take both keys. the issue is more, we cannot
> just swap left and right, not even for multiply and addition. that may work
> for natural numbers, but not for a zillion other cases. [...] so yes, both
> keys, obviously. single keyed is an oversight of ours" — user

Read that ticket before starting. It contains the full design: the second key
must match by **compatibility with precedence** (exact type + `RecName` first,
then a `Variant` parameter as a wildcard fallback), the strong recommendation to
route selection through `MatchCallDelphiProcAddr`'s existing ranking rather than
hand-rolling a second matcher, and the open sub-question of what the unary and
conversion operators (`:=`, `Explicit`, `Inc`, `Dec`, `Enumerator`) store in the
second key.

## Why this ticket exists at all — the decision was never re-filed

Track U's rule is that a decided item which turns out to be plain work is
re-filed into the owning lane. That did not happen here: the decision has sat in
`decided/` since 2026-08-10, referenced only by the `done/` ticket that raised
it. `decided/` is not scanned by `ready`/`next`, so the work was **invisible to
the queue** — and on 2026-08-16 the same bug was rediscovered from scratch while
implementing [[bug-nilpy-no-complex-number-type]], measured again, and written up
again as a new ticket before the search that found the decision.

That is the cost of not re-filing, and it is worth stating plainly because the
rediscovery was not cheap.

## Measured again 2026-08-16 (same symptoms, six days later)

```pascal
type TCx = class re, im: Double; end;

operator + (a, b: TCx): TCx;         { pxx: ok        FPC: ok }
operator + (a: TCx; b: Double): TCx; { pxx: ok        FPC: ok }
operator + (a: Double; b: TCx): TCx; { pxx: REFUSED   FPC: ok }
operator + (a: Integer; b: TCx): TCx;{ pxx: REFUSED   FPC: ok }
```

| declaration | pxx says |
| --- | --- |
| `(a: Double; b: TCx)` | `operator: cannot determine operand type` |
| `(a: Integer; b: TCx)` | `impossible operator overload: this operation is predefined for built-in operand types` |

FPC compiles and runs both; `1.5 + MkCx(1,2)` prints `2.5` under FPC and does
not build under pxx.

Two diagnostics because the `Double` row fails one step earlier: the declaration
lookahead (`parser.inc:2566-2591`) maps only four builtin type TOKENS back to
names (`tkInteger_T`, `tkBoolean_T`, `tkChar_T`, `tkString_T`), so `Double`,
`Real`, `Single`, `Int64`… leave `typeName` empty. The *scalar* resolution just
below already handles `'double'`/`'real'`/`'extended'`/`'single'` **by name**, so
only the token→name step is missing. Note the first three rows: a mixed
`(TCx, Double)` overload IS accepted, so this is not the "one overload per
operator per type" limit that `lib/rtl/ucomplex.pas:5-17` records — it is
specifically a built-in type on the LEFT.

## The trap — do NOT just relax the guard

`parser.inc:2738-2741` refuses when the FIRST operand is not a record/class:

```pascal
{ ...at least one operand must be a record/class }
if recId = REC_NONE then
  Error('impossible operator overload: this operation is predefined for built-in operand types');
```

The comment states the rule correctly and the code checks one operand. **But
fixing the check alone is worse than leaving it**, and the decide ticket is
explicit about why: the table is keyed on the LEFT operand, so a scalar-left
operator would register under `(tkStar, tyInteger, REC_NONE)` — and since the
lookup consults the left operand, **plain `3 * 5` would then match it** and
compile into a call to the record operator. A wrong refusal becomes a silent
wrong value in arithmetic that has nothing to do with the record.

That is the whole reason the current refusal is the *safe* answer today, and why
the second key has to land first. The 2026-08-16 rediscovery wrote up
"accept when EITHER operand is a record/class" as its fix shape and would have
walked straight into this had it been implemented; it was not.

## The use site is left-keyed too

`FindOpOverload2` is only consulted when the LEFT operand is a record/class:

```pascal
if (IntToTypeKind(ASTTk[left]) = tyRecord) or (IntToTypeKind(ASTTk[left]) = tyClass) then
  opci := FindOpOverload2(...);        { parser.inc:17199-17201 }
```

Its own header comment records the left-only key as a known compromise ("Rather
than widen the table, disambiguate here") — and a built-in left operand is the
case that compromise cannot cover, because there is nothing to disambiguate
from. Per the decision this is cheaper than it looks: all three binary use sites
already compute and pass the right operand, so the remaining work is the second
key column plus matching on it.

## Scope

Pascal operands first. NilPy does not use this table — its operators go through
the dunder protocol — so a Variant or promotable-int operand only reaches the
second key when NilPy loads a Pascal unit that overloads operators. Do not build
promo/variant-payload ranking on speculation (user, 2026-08-10).

## Gate

The four-row table above as a test with FPC's column as `.expected`; a negative
test pinning that `3 * 5` still compiles to plain arithmetic with a
`(Integer, TCx)` operator in scope — that is the miscompile this ticket exists to
make impossible; `test/test_op_overload.pas` and `lib_ucomplex.pas` staying
green; `make compiler/pascal26` (self-host fixedpoint); `tools/gate.sh quick`.
