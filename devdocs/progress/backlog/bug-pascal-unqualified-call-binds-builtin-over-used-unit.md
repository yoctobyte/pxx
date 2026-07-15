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

## Disposition (2026-07-15) — DEFAULT IS INTENDED, not a bug to fix

After discussion with the user (the repo owner): the lax overload-compete is
**intended, first-class pxx behaviour**, not a defect. builtin / RTL / libraries
overriding by name is how the whole architecture selects implementations (e.g.
platform softfloat-in-builtin). FPC just chose a different rule (a same-name decl
HIDES System); that difference belongs behind the compatibility switch, NOT in a
default-resolution change. So: **no default change, no resolution surgery.**

- Real-world impact removed by [[bug-lib-test-console-solitaire-flaky]] Part B
  (rtl/random no longer shadows the System names).
- FPC-parity strictness delivered as [[feature-strict-fpc-umbrella]]: `--strict-fpc`
  bundles case/operator/visibility/require-forward. `StrictOverload` (which would
  ERROR on a System-name shadow) is a **standalone** flag, kept out of the umbrella
  because our RTL uses undirectived overloads by design and bundling it would fail
  to compile the corpora — and directive boilerplate across the RTL is refused.

Left in backlog only as a reference (minimal repro + root cause above). The one
remaining "could do": make `StrictOverload` usable against the lax RTL (scope it
so it polices user code without choking on pulled units) — low value, no owner.
Not a default correctness bug.
