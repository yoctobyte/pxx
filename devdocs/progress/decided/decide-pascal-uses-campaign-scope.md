---
track: U
prio: 55
type: decide
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — option 2, combined with the class-namespace fix

**User's call: 2** (close the `builtin`/`builtinheap` instrumentation gap
first, get a true count, then size the real campaign) — matches the
2026-08-01 correction above. Also: this isn't really two separate future
campaigns. [[decide-class-namespace-scoping]] already root-caused the
`tkinter.Canvas`/reportlab `Canvas` collision to this exact same
non-transitive-`uses` gap — fixing real `uses` scoping IS the
class-namespace fix, viewed from a different symptom. Sequence as one
effort: fix `VisibilityAllows` to exclude `builtin`/`builtinheap`, re-measure
for a true count, then land the real non-transitive rule — which closes
both the class-collision problem and the RTL leak problem together, not as
two things to coordinate separately.

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

## 2026-08-01 — correction: the number above is inflated, real scope is smaller

Verified directly (`compiler/symtab.inc`'s `VisibilityAllows`, and
`compiler/builtin/pylib.pas`'s actual `uses` clause) rather than trusting
the raw count:

- `builtin`/`builtinheap` are pxx's own `System`-unit equivalent —
  deliberately ambient everywhere by design (every Pascal dialect
  auto-includes `System`), not a leak. `VisibilityAllows` has no special
  case for this yet, so it counted these the same as any other pair —
  meaning the `pylib -> builtinheap` (6894), `sysutils -> builtinheap`
  (4522), `pylib -> builtin` (4145) etc. hits, which dominate the 81-pair
  count, are measurement noise from an instrumentation gap, not real work.
  **Fix the instrument first** (exclude `builtin`/`builtinheap` from
  detection) before re-measuring — this changes the true number
  substantially, likely by most of an order of magnitude given how much of
  the raw count those three lines alone account for.
- `pylib -> sysutils` (1717) isn't one thing either: `pylib.pas` has no
  `uses sysutils` anywhere in its own code (confirmed by reading it) — most
  of that count is genuine accidental leakage that closes for free once
  real scoping lands. The one deliberate exception is `pylib.Exception`
  merging with `sysutils.Exception`, already anticipated by
  [[decide-class-namespace-scoping]]'s own resolution — needs exactly one
  explicit `uses sysutils` added to `pylib.pas`, not a rewrite.
- Full detail in [[bug-pascal-uses-is-transitive]]'s 2026-08-01 correction
  note.

**Guiding principle for the fix, regardless of which sequencing option is
picked:** what matters is that USER programs get a clean namespace.
Internal RTL-to-RTL sharing (like the `Exception` merge) is fine as long as
it's deliberate, declared explicitly, and doesn't leak unrelated surface to
callers — the fix does not need to eliminate every internal cross-unit
reference, only the accidental, undeclared ones that reach a program's own
namespace.

This makes **option 2 (close the instrumentation gap, get a true count,
then decide)** more clearly correct than it looked before — the
`builtin`/`builtinheap` exclusion alone is small, well-scoped work that
should land before any campaign-sizing decision, since it's likely to show
the real problem is meaningfully smaller than "hundreds of files."

## What unblocks on this

[[decide-class-namespace-scoping]] and `bug-nilpy-stdlib-name-binds-pascal-unit`
both cite this as their root cause; resolving this decides whether they land as
part of the same campaign or stay worked around individually.

## 2026-08-01 — option 2 executed: instrument fixed, true count is 35 pairs

The decided first step (close the instrumentation gap, re-measure, then size)
is **done**. Full detail in [[bug-pascal-uses-is-transitive]]'s
"instrument fixed, TRUE count" section; the sizing-relevant summary:

- **Two** ambient-System artifacts were inflating the count, not one. Beyond the
  `builtin`/`builtinheap` case this ticket already identified, classifying the
  leftover `-> <program>` bucket showed it was **100% `TObject`/`TGuid`** —
  compiler-minted System intrinsics stamped with `CurrentUnitIdx = -1`. Both are
  now excluded from detection; the `-> <program>` bucket is 0.
- Re-measured over **all 934** `test/*.pas` (the old figure came from 80):
  **35 distinct pairs / 4721 hits**, against the previous headline of **81 pairs
  from 80 files**. Less than half the pairs, from twelve times the code.

**Re-sizing verdict: this is NOT a campaign.** The thing that made it look like
one — "hundreds of files need a mechanical `uses builtin[heap]`" — was entirely
the artifact and that work does not exist. What is actually left is 35 RTL-internal
unit pairs, every one of them either a deliberate dependency needing one explicit
`uses` line (the `pylib`/`sysutils` `Exception` merge being the known case) or
accidental leakage that closes for free when real scoping lands. **No
user-program-facing leak appears anywhere in the corpus.**

That matches this ticket's own guiding principle (what matters is that USER
programs get a clean namespace) — and by that standard the corpus is already
clean; the remaining work is tidying RTL-internal wiring.

### Suggested next step, not yet decided

The remaining unknown is the instrument's OTHER gap, still open: it does not
catch names resolved through `IRFindProc1ByArgTk`/`MatchProcCall` (the ticket's
own headline `IntToStr` repro still does not warn), so 35 is a floor, not a
ceiling. Closing that gap is the natural next measurement before enforcement
lands. Worth doing before writing the real non-transitive rule, on the same
"measure, don't reason" grounds that just cut this estimate in half twice.
