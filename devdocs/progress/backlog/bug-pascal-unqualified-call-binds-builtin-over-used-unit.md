---
summary: "SILENT: a builtin System routine (Random) OVERLOAD-COMPETES with a same-named routine from an explicitly-used unit instead of being HIDDEN by it (FPC: a non-`overload` unit routine hides System). Differing param widths (unit Integer vs builtin Int64) let the arg TYPE steer the pick — a literal binds the unit, a wider expression binds the builtin"
type: bug
track: P
prio: 40
---

# unqualified call binds to a System builtin over a uses'd unit's routine

- **Type:** bug — **SILENT** wrong resolution. Track P (Pascal frontend name
  resolution). Split out of [[bug-lib-test-console-solitaire-flaky]] (Track B),
  whose surface fix qualified the calls; this is the root defect.
- **Found:** 2026-07-15 diagnosing the solitaire flake.

## Symptom

In `examples/solitaire_gui/klondike.pas` `NewGame`:

```pascal
uses random;   // unit random: RandSeed(proc) + Random(func), xoshiro
...
RandSeed(LongWord(seed));   // -> unit random.RandSeed (a CALL; builtin RandSeed is a VAR)
for i := 51 downto 1 do
  j := Random(i + 1);       // -> the compiler's BUILT-IN System Random (xorshift32) !!
```

`RandSeed(seed)` bound to unit `random`'s procedure (seeded xoshiro), but the
unqualified `Random(i+1)` bound to the **built-in** System `Random`
(`compiler/builtin/builtin.pas`, xorshift32 over its own `RandSeed: Cardinal`
state var — never seeded here). So the Fisher-Yates shuffle drew from the
unseeded builtin generator: the deal (and everything downstream) was
non-reproducible despite a fixed `NewGame(1)` seed. Qualifying `random.Random`
fixed it (verified 20/20 deterministic).

FPC rule (and Delphi): an identifier from an **explicitly used unit** shadows the
System/built-in one for unqualified references — so `random.Random` should win.
pxx bound the builtin instead. Silent: no diagnostic, just wrong values.

## MINIMAL repro (nailed 2026-07-15)

The trigger is NOT multi-unit interaction — it is the **argument form**, because
the two `Random`s have different parameter widths and the arg type steers the
overload pick:

- `compiler/builtin/builtin.pas`: `function Random(range: Int64): Int64;` (pulled
  via the bare-name pre-scan when a `Random(` token is seen).
- old `lib/rtl/random.pas`: `function Random(n: Integer): Integer;` (xoshiro).

A unit that `uses random` and calls both:

```pascal
unit k2; interface procedure Go(seed: Integer); implementation uses random;
procedure Go(seed: Integer); var i, x: Integer;
begin
  RandSeed(1);                 { -> unit random.RandSeed (proc; builtin RandSeed is a var) }
  i := 5;
  x := Random(1000);          { -> unit random.Random  (1000 is tyInteger, exact rank 0) }
  x := Random(i + 1);         { -> BUILT-IN Random      (i+1 typed wider -> Int64 ranks better) MISBIND }
end; end.
```

`Random(1000)` binds the unit (literal is tyInteger → exact fit to the unit's
`Integer` param, rank 0; the builtin's `Int64` param is rank 1). `Random(i + 1)`
binds the **builtin** (the expression is typed wide enough that `Int64` fits as
well or better). So `RandSeed` seeded xoshiro while `Random(i+1)` drew from the
never-seeded builtin — non-reproducible. Confirmed with per-run deal dumps.

## Root cause

pxx treats the pulled builtin `Random` and the used unit's `Random` as one
**overload set** and ranks candidates by argument fit (`OverloadArgRank`). FPC/
Delphi don't: a routine from an explicitly-used unit that is NOT marked
`overload` **HIDES** the System/builtin one entirely — the arg type is
irrelevant, the unit version always wins. The machinery for this already exists
(`HasNonOverloadProc`, `symtab.inc`), but the call-site candidate gathering still
includes the builtin.

## Direction

At the call site, when `HasNonOverloadProc(name)` is true for a non-builtin
routine in scope, EXCLUDE builtin-unit candidates (procs whose `ProcUnitIdx`
is the `builtin` unit) from the overload set — the builtin is a fallback only,
reached when nothing else declares the name. Core resolution change (touches
every call): gate = make test + self-host byte-identical + conformance/fpjson/
Synapse. Test against the k2 repro above, FPC-differential.

## Disposition v1 (2026-07-15) — SUPERSEDED: "intended, no fix"

Originally closed as intended: lax overload-compete is first-class pxx (builtin/
RTL override by name = how impl selection works), FPC's hide rule belongs behind
`--strict-fpc`. That call conflated TWO questions (see v2).

## Disposition v2 (2026-07-17) — FIXED as a default correctness bug

The v1 call answered only **Q1** (*who wins on a name collision — builtin or
used-unit?*), where "lax, builtin overridable by name" is a defensible dialect
choice. It never addressed **Q2**: *when both are in the set, is the winner
STABLE across call sites, or does arg width flip it?* Q2 is the real defect and
is independent of FPC parity:

- Overload resolution assumes overloads are interchangeable impls of one
  operation differing only in accepted types. builtin-vs-used-unit violates that:
  they are different implementations with **independent state** (two RNGs).
- So arg width silently routed `Random(1000)` → unit and `Random(i+1)` → builtin
  inside one body: **split-brain, silent, non-reproducible, refactor-fragile**
  (a type change elsewhere reroutes which code runs). Emits **wrong values**, no
  diagnostic — which by the repo's own escape rule promotes a compat finding to a
  real `bug-` (silent wrong behavior is not a parkable parity difference).

**Fix (commit below):** builtin unit is **fallback-only**. On a plain unqualified
call, if any non-builtin routine of the name is in scope, all builtin-unit
candidates are demoted out of the overload set — **name-level, not
arg-width-level**. The used unit then owns the whole set; the builtin is reached
only when nothing else declares the name (softfloat / platform intrinsics, which
no user unit shadows, are unaffected). `System.X` (qUnit = -2) keeps the builtin,
preserving the explicit-System escape hatch.

Why this is right and NOT a `--strict-*` matter: a default silent miscompile is
not "fixed" by a non-default flag most code never sets. `--strict-fpc` still owns
**hard FPC parity** (error on a used-unit shadow, demand the `overload`
directive, `{%FAIL}` conformance) — a separate, opt-in policy layer. The v1
blocker ("RTL uses undirectived overloads, StrictOverload would fail the corpora")
conflated **intra-unit** overloading (legit, untouched) with the **cross-origin**
builtin-vs-unit collision this fix scopes to; no directive boilerplate needed.

Implementation: `MatchProcCall` gains `suppressBuiltin`; `BuiltinUnitIdx` caches
`InternStr('builtin')`; `MatchElig` gates every match phase. Guard test
`test/test_builtin_name_demote.pas` (+ `test/builtin_shadow/myrand.pas`). Gate:
`make test` GREEN, self-host byte-identical (reseeded), testmgr quick GREEN;
matrix/corpus (fpjson/Synapse/cross) offloaded to Track T at the pushed SHA.
