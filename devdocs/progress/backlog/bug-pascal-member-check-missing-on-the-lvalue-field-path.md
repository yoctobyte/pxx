---
track: P
prio: 45
type: bug
summary: "RequireRecMember has 3 call sites, all expression paths, and ~20 AN_FIELD construction sites exist. A breakpoint proved the statement-LVALUE path never calls it. No longer a silent wrong store (RecFieldType now rejects), but the guard is inconsistent and its coverage is unaudited."
---

# The member check is missing on the statement-lvalue field path

- **Type:** bug (missing diagnostic / inconsistent guard) — **Track P**
  (member resolution, shared `parser.inc`)
- **Opened:** 2026-08-03 by claude-P@opus5 as the deliberate remainder of
  [[bug-pascal-unknown-record-field-accepted-in-compiler-source]].
- **Not urgent:** the silent-wrong-store half is fixed. This is the consistency
  half.

## Measured

`RequireRecMember` (`parser.inc:3612`) has exactly **three** call sites —
`parser.inc:6176`, `7421`, `7589` — and all three are expression paths. There
are ~20 `AllocNode(AN_FIELD)` sites.

A breakpoint on the guard, running the compiler over a tree containing
`Syms[0].Bogus := -1`, was **never hit**: the statement-lvalue path builds its
`AN_FIELD` without ever consulting it. That was measured with a `-g` compiler
and gdb, not inferred.

## Why it is no longer producing wrong values

The parent bug's fix rejects at the point the miss is *decided*, inside
`RecFieldType`'s builtin-record branch. That is path-independent, so it catches
the lvalue path too — for **builtin-mirrored** records.

For a **user** record (`recId >= REC_UCLASS_BASE`) reached purely through the
lvalue path, the guard is still not called; whether a bad member is caught then
depends on other checks downstream. No repro is known that gets through — four
minimal shapes are all correctly rejected — which is precisely why this is an
audit rather than a bug report with a failing case attached.

## The work

1. Enumerate the ~20 `AllocNode(AN_FIELD)` sites and classify each: expression
   vs lvalue, and which frontend it serves.
2. Add `RequireRecMember` to every Pascal path that lacks it. It is safe by
   construction on the sites that do not need it — it no-ops unless
   `recId >= REC_UCLASS_BASE` and `FindUField` misses.
3. **Do not add it blind to NilPy paths.** `parser.inc` is shared, and NilPy
   objects have dynamic attributes, so a member miss there can be legitimate.
   Gate on `not isNilPy` where a shared site serves both.
4. Consider collapsing the three existing call sites and the new ones into the
   single place the field's type is resolved, so the count cannot drift again —
   the same argument the parent bug's fix used.

## Gate

An unknown member on a user record errors identically whether it is written as
an lvalue (`r.nope := 1`), read in an expression (`x := r.nope`), or passed as
an argument; NilPy dynamic attribute access is unaffected (`test-nilpy` green);
self-host fixedpoint byte-identical; `gate.sh quick` green.
