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
