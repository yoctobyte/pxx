---
slug: bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets
track: P
prio: 65
type: bug
blocked-by: []
summary: "`SizeOf(Extended)` answers 10 while a variable declared `Extended` occupies 8 and an array of four occupies 32. Same two-table split as [[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]], in the same function, left unfixed for the sibling type when Real was corrected. Self-inconsistent within our own compiler, so any stride or GetMem computed from SizeOf(Extended) is two bytes too long per element."
status: float
---

# `SizeOf(Extended)` disagrees with the storage `Extended` gets

Found 2026-08-29 while validating a float-residency probe: a local declared
`Extended` was assigned a float resident register, which the residency pass
restricts to `tyDouble`. It was not a residency bug — `Extended` really is
`tyDouble` here — but the type-name table disagrees.

## Measured (2026-08-29, x86-64, `-O2`)

```
                                   pxx        fpc
SizeOf(Extended)=                   10         10
SizeOf(e)      where e: Extended     8         10     <- pxx self-inconsistent
SizeOf(array[1..4] of Extended)     32         40
```

**The FPC column is not the bug.** `Extended` aliasing `Double` is deliberate —
`feature-extended-alias-or-reject`, and `pasparser_lval.inc:6291` says so in
as many words: *"`Extended` aliases Double on every target"*. Answering 8/8/32
throughout would be correct and is what this ticket asks for. The defect is
that **pxx contradicts itself**: 10 from the type name, 8 from a variable of
that type, and 32 for an array of four of them.

## Cause — the same two tables, the same function, the sibling case

`compiler/pasparser_lval.inc` resolves a type name twice:

- **~6295, `BuiltinScalarTypeKind`** — the DECLARATION path.
  `double | extended | valreal | tdatetime | currency` -> `tyDouble`.
- **~6408, the `SizeOf` table** — `else if CaseEqual(nm, 'extended') then
  Result := tyExtended`.

`tyExtended` is ordinal 20 and sizes as the 10-byte x87 type; `tyDouble` is 19
and sizes 8. So the two paths disagree for exactly one type name.

This is the unfixed arm of a double case that was already found and fixed on
its other arm. The comment sitting **six lines above** the offending line
describes the identical failure for `Real`:

> *"`Real` is the target's NATIVE float depth, not an alias for Double ... This
> line used to say tyDouble outright, and since SizeOf consults THIS table and
> declarations consult BuiltinScalarTypeKind, `SizeOf(Real)` answered 8 on those
> targets for a variable that occupied 4."*

CLAUDE.md's rule for this is explicit — *if you fix a bug on one arm of a double
case, grep for the sibling before closing the ticket* — and
`devdocs/dev/normalise-dont-special-case.md` is the argument for why the second
path is the one that stays broken. `Extended` was the sibling and it was not
grepped for.

## Why it is a bug and not a compat item

By the compat table in CLAUDE.md this is the *silent wrong behaviour* escape,
not a parity item: nothing here is about matching FPC. A stride, `GetMem`,
`Move` or `FillChar` size computed from `SizeOf(Extended)` is **two bytes too
long per element** against storage that is genuinely 8, so walking an
`array of Extended` with that stride desynchronises after the first element and
reads into the next. No diagnostic, wrong values, far from the cause.

## Suggested fix

Make the `SizeOf` table agree with the declaration path: at
`pasparser_lval.inc:6408`, `extended` -> `tyDouble`. Then check the rest of that
table against `BuiltinScalarTypeKind` in the same pass rather than one name at a
time — `valreal`, `tdatetime` and `currency` are mapped to `tyDouble` by the
declaration path and should be confirmed, not assumed, on the `SizeOf` side.

Whether `tyExtended` should continue to exist at all once nothing produces it is
a separate question and probably a Track U one: `EmitStoreVar`'s `tk =
tyExtended` arm emits an x87 `fldl`/`fstpt` pair that no declared variable can
currently reach.

## Repro

```pascal
program ext;
var e: Extended; a: array[1..4] of Extended;
begin
  Writeln(SizeOf(Extended), ' ', SizeOf(e), ' ', SizeOf(a));   { 10 8 32 }
end.
```

## Gate

Track P: `make compiler/pascal26` (the self-host fixedpoint) plus this repro
printing three consistent numbers.

## Parked in `float/` 2026-08-30 — with a caveat worth re-reading

Moved `backlog_new/` → `float/` with the rest of the `Extended` cluster, at the
owner's request, so the whole set can be worked in one consolidated session
(umbrella: [[feature-a-extended-is-an-alias-for-double]]).

**Two consequences to be aware of, because they cut against each other:**

1. **This ticket is NOT blocked by the umbrella and should not wait for it.**
   It is a self-inconsistency inside the *current alias*, not a step toward
   80-bit Extended. Confirmed on this tree 2026-08-30: `:6417` is the **only
   site in the whole compiler that produces `tyExtended`** — every other
   reference (`ir_codegen.inc`, the backends, `cparser.inc:133`/`:172`) is a
   consumer firing only on an already-Extended operand. Fixing it makes
   `tyExtended` genuinely dead, which is the cleanest possible starting position
   for the umbrella: both tables then move together, in one place, instead of
   the split having to be re-merged first. It makes the big job smaller.

2. **`float/` is never scanned by `ready`/`next`, so this prio-65 bug is now
   invisible to the ranker.** That is the intended cost of parking, but note
   this ticket is arguably not Track F at all by the folder's own rule — *rank
   the mechanism, never the datatype.* Its subject is a two-table disagreement
   producing a wrong `SizeOf`, and its damage is a stride two bytes too long per
   element walking an `array of Extended`: silent wrong values, far from the
   cause. That is the mechanism, and the `Extended` content is incidental — the
   same defect on the `Real` arm was fixed as an ordinary Track A bug.

   It is parked here because the owner asked for the cluster to be consolidated,
   which is a decision about *attention*, not a reclassification. **If the
   consolidated session does not happen soon, move this one back to `backlog/`
   on its own** — it is a one-line fix at `pasparser_lval.inc:6417` plus the
   audit of the sibling names (`valreal`, `tdatetime`, `currency`) that the
   Suggested fix already asks for, and it does not need the session.
