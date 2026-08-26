---
slug: regression-test-core-test-arrayofconst-to-method-b287
title: "regression: an `array of const` literal to a method stopped parsing"
track: P
prio: 70
type: regression
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
summary: "Auto-filed by twatch. Caused by 547163758 (the single-candidate method argument type-check): making nCand = 1 take the speculative-probe route exposed that the probe cannot parse a `[...]` argument at all — ParseArgExpr has no parameter to bind against, so it reads the bracket as a SET literal and dies on `set item must be one character`, and Error halts before the probe's own unsupported-shape escape. Answered before the probe runs, the way the NilPy `**` case already is."
---

# `TC.Log('class: %s = %d', ['answer', 42])`

Auto-filed by the Track T watcher on plexus, 2026-08-26T16:41:03Z. Bisected
range: bad `a195f67d754b`, last good `90892318c94c`. The named sha touches no
buildable file; the only compiler commit in the range is `547163758`, which is
mine from earlier today.

## Repro

`test/test_arrayofconst_to_method_b287.pas`, at HEAD:

```
pascal26:22: error: set item must be one character
  near:  Log  class: %s = %d   >>> answer
```

## Cause

[[bug-p-a-single-candidate-method-call-does-not-check-its-argument-types]]
changed `FindUMethOverloadAhead`'s `nCand <= 1` shortcut to `nCand = 0`, so a
one-candidate method call now takes the speculative-probe route instead of
returning straight from `FindUMethArity`. The probe parses each argument with
`ParseArgExpr` to learn its type — and `ParseArgExpr` has no parameter to bind
against, so a `[...]` argument is read as a **set literal**. `['answer', 42]`
is not a set, and `Error` halts, so the probe's own "probe disagreed with the
token-level count (an unsupported arg shape)" escape further down is never
reached.

Worth naming plainly: the probe has never been able to parse this shape. What
changed is only *which* calls reach it. The same halt was already latent for a
genuinely overloaded method taking `array of const`.

## Fix

Answer the shape **before** the probe runs, which is the idiom this function
already uses for the NilPy `**` case ("cannot parse a `**` at all"). Two
conditions, both required:

- some argument STARTS with `[` at bracket depth 0 (new `ArgListHasBracketElem`,
  token-level, the same scan shape as `PyArgListHasStarElem`), **and**
- some arity-viable candidate has an open-array parameter.

Either alone is fine on its own: a bare `[` really may be a set, which parses;
an open-array parameter really may be handed a variable, which also parses. It
is the combination the probe cannot survive.

On a hit, selection falls back to `FindUMethArity` — exactly what these calls
had before the probe existed, so nothing regresses relative to the state before
`547163758`. What it does NOT buy is type-based rejection for those calls;
making the probe parameter-aware is
[[refactor-p-the-overload-probe-cannot-see-the-argument-match-channels]], which
is the ticket for giving the probe the argument-match channels the free path
already has.

## Outcome

Fixed in `compiler/pasparser_call.inc`. `test-core#src:test/test_arrayofconst_to_method_b287.pas`
GREEN. The three tests that guard the change which caused this —
`test_method_arg_typecheck_fails.pas`, `test_method_arg_typecheck_ok.pas`,
`test_method_overload_types_b248.pas` — all still GREEN, so the type-check the
regression came from is intact.

Corpora: pascal-conformance 346/0/170/34 and fgl 7/7, both unchanged.
`gate.sh quick` GREEN.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
