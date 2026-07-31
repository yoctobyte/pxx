---
track: U
prio: 55
type: decide
---

# Decide: how should the `uses`-is-transitive fix be scoped and sequenced?

Raised 2026-07-31 from [[bug-pascal-uses-is-transitive]], after landing that
ticket's measurement step (`--warn-uses-leak`, an edge table +
`VisibilityAllows`, opt-in and read-only — see that ticket's "Measurement step
LANDED" section for the mechanism).

## The number

A sample run over the first 80 of `test/*.pas` (923 total; `lib/rtl` and the
NilPy `.npy` corpus not yet run) already shows:

- 81 distinct (importer, provider) unit pairs.
- Every RTL/pylib unit reaches `builtinheap`/`builtin` without declaring it —
  today's ambient intrinsic surface. A real non-transitive rule needs an
  explicit `uses builtin[heap]` added to every one of those units.
- Heaviest offenders by hit count: `pylib -> builtinheap` (6894),
  `sysutils -> builtinheap` (4522), `pylib -> builtin` (4145),
  `http -> builtinheap` (3808), `pylib -> <program>` (3276, class lookups),
  `ecdsa_p256 -> builtinheap` (2980), `bignum -> builtinheap` (2548),
  `pylib -> sysutils` (1717), `zlib -> builtinheap` (1596).
- The instrument itself has a known gap: it doesn't yet catch the ticket's own
  headline repro (`IntToStr` reached transitively through an
  implementation-section `uses`) — that resolves through
  `IRFindProc1ByArgTk`/`MatchProcCall`, not the `FindProc` lookup the warn
  hook is wired into today. The real count is higher than what's above.

## The fork

1. **One campaign, land the real rule + fix everything it breaks in one
   sustained effort.** Correct end state fastest, but "hundreds of files,
   mechanical `uses builtin` additions" is still hundreds of files to touch and
   verify, plus closing the `IRFindProc1ByArgTk` instrumentation gap first to
   know the true size.
2. **Phase it: close the instrumentation gap first, get a true count, THEN
   decide size/sequencing.** Lower risk of committing to a shape that turns out
   too small once the call-classification path is counted too.
3. **Don't chase this now — descope back to backlog at low prio.** The current
   laxity is silent-but-harmless in every corpus that currently compiles (no
   open regression traces to it); the payoff is future collision avoidance
   (`decide-class-namespace-scoping`) and NilPy stdlib-name hygiene
   (`bug-nilpy-stdlib-name-binds-pascal-unit`), not a fix for something broken
   today.

No recommendation baked in here on purpose — this is a sizing/sequencing call,
not a technical one; the measurement ticket already did the technical part.

## What unblocks on this

[[decide-class-namespace-scoping]] and `bug-nilpy-stdlib-name-binds-pascal-unit`
both cite this as their root cause; resolving this decides whether they land as
part of the same campaign or stay worked around individually.
