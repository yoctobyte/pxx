---
summary: "SILENT: an unqualified routine call can bind to a System BUILTIN (e.g. Random) instead of a same-named routine from an explicitly-used unit — klondike's `Random` drew from the unseeded builtin, not `uses random`'s xoshiro, so a fixed-seed shuffle was non-reproducible"
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

## Not-yet-minimal — the trigger is elusive

Isolated repros did **not** reproduce (all deterministic = unit won correctly):
- program `uses random` directly; RandSeed(1)+Random → deterministic.
- program → mid unit `uses random` → deterministic (transitive).
- same, plus a builtin `Random(100000)` call in main → still deterministic.

It only misbinds in the full `console_solitaire` build
(`uses screen, sysutils, klondike;` where `klondike uses random`). So the trigger
is some **multi-unit interaction** — unit compile order, the builtin bare-name
pre-scan (`Random`/`Randomize`/`RandSeed` are pulled like `Str`/`Val`), or a
same-named surface pulled by a sibling unit — not the plain `uses random`
transitive case. Repro: `stable -Fulib/rtl -Fuexamples/solitaire_gui
examples/solitaire/console_solitaire.pas /tmp/cs` with the pre-fix klondike, dump
the first dealt cards after the shuffle → they differ every run.

## Direction

Nail the trigger (bisect the uses list of console_solitaire until the misbind
appears), then make unqualified resolution prefer an explicitly-used unit's
routine over a System builtin of the same name (the builtin bare-name pre-scan
must lose to a real uses'd symbol — the "user declaration shadows" rule the
builtin comments already claim). Add an FPC-differential regression once minimal.

## Acceptance

A minimal multi-unit repro where an unqualified `Random` (or any builtin-named
routine) resolves to the used unit's version, FPC-differential identical; the
klondike qualifiers can then be dropped and the deal stays reproducible.
