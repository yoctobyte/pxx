---
slug: bug-p-a-generic-type-parameter-is-unknown-when-a-specialization-is-materialised-cross-unit
track: P
prio: 65
type: bug
status: backlog
blocked-by: []
summary: "Compiling a program that uses Generics.Collections dies with `unknown type: TKey` at generics.defaults.pas:790 — a line that declares `function Equals(constref ALeft, ARight: T): Boolean; override;` inside `TDelegatedEqualityComparerEvents<T>`, whose only type parameter is T. `TKey` is the OUTER argument name from the collections side, so an outer specialization's parameter name is leaking into a generic class materialised in another unit instead of being substituted. NOT MINIMISED — one observation from the corpus, no reduced repro yet."
owner: unassigned
---

# A generic type parameter is `unknown` when a specialization is materialised cross-unit

Found 2026-08-29 by frankA, immediately after
[[bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body]] let
`generics.defaults.pas` compile end to end for the first time. This is the wall
that appears **behind** it, so it is newly reachable rather than a regression.
Rung 9 of [[feature-pascal-corpus-expansion]].

## Observation

```
$ pascal26 -Fu<rtl-generics src> drv2.pas out       # drv2 = `uses Generics.Collections`
pascal26:790: error: unknown type: TKey
  in: .../generics.defaults.pas
  near:  constref ALeft  ARight  >>> TKey
pascal26: too many errors, stopping
```

`generics.defaults.pas:785-790` is:

```pascal
  TDelegatedEqualityComparerEvents<T> = class(TEqualityComparer<T>)
    ...
    function Equals(constref ALeft, ARight: T): Boolean; override;
```

The declared parameter is **`T`**. `TKey` appears nowhere in that class — it is
the type-parameter name used on the **collections** side. So the name being
resolved at materialisation time is the OUTER specialization's parameter rather
than the substituted argument, in a class that lives in a DIFFERENT unit.

`generics.defaults.pas` on its own (`uses Generics.Defaults`) compiles clean, so
this needs the cross-unit specialization to appear.

## Status — deliberately not diagnosed

**One observation, no minimal repro.** The shape above is read off the error and
the source; it is a description of what was seen, **not a measurement of the
mechanism**, and it should not be quoted as one. This repo has a standing habit
of a plausible reading hardening into a recorded root cause — see
[[bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body]], where
two readings taken straight from the corpus error were both wrong and the
minimal repro settled it in one step.

So the first job here is a reduction: two units, an outer generic in one
specializing an inner generic in the other, and see whether the outer parameter
NAME or the substituted argument reaches the inner declaration.

## Related

- [[bug-p-two-different-nested-specializations-of-one-template-collide]] (p65) —
  also nested-specialization materialisation; may or may not be the same
  mechanism. Worth checking before diagnosing either.
- [[feature-pascal-corpus-expansion]] — the ladder this came from.

## Gate

`uses Generics.Collections` compiles; `generics.defaults.pas` keeps compiling on
its own; a reduced two-unit repro in `test/`; the per-fix loop.

## Two hypotheses already REFUTED by measurement (2026-08-29, frankA)

Recorded so the next holder does not spend them again. Neither is the cause.

**1. "It is the `{$DEFINE X := ...}` macros."** `generics.collections.pas:30`
turns `{$MACRO ON}` on and defines its type-parameter lists as macros —
`{$DEFINE TREE_CONSTRAINTS := TKey, TValue, TInfo}` — which are then used as
generic parameter lists (`TCustomAVLTreeMap<TREE_CONSTRAINTS>`, :638). Since the
error names `TKey`, a macro expanding literally in the wrong scope is the
obvious first suspect. Measured, both work and match FPC:

```pascal
{$MACRO ON}
{$DEFINE MYT := Integer}    var x: MYT;                  -> 42   (fpc: 42)
{$DEFINE PARAMS := TA, TB}  type TPairX<PARAMS> = record -> 7 x  (fpc: 7 x)
```

So macro substitution is supported, and a macro expanding to a comma-separated
generic parameter LIST is supported. Whatever fails needs more than this.

**2. "It is the `&`-escaped identifier / the forward-decl case bug."** No —
that was the PREVIOUS wall
([[bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body]], fixed).
This wall is what appears behind it. `generics.defaults.pas` compiles end to end
on its own; the failure needs `uses Generics.Collections`.

### What that leaves

The distinguishing feature is still **cross-unit**: an outer specialization in
`collections` materialising a generic class declared in `defaults`, where the
outer parameter NAME rather than its substituted argument reaches the inner
declaration. That remains the description-from-the-error, not a measurement —
the reduction (two units, outer generic specializing an inner one) has NOT been
built yet, and is still the first job.
