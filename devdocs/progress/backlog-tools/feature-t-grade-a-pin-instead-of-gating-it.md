---
track: T
prio: 85
type: feature
status: open
found: 2026-09-01
found-by: frank-user
---

# Grade a pin instead of gating it, and say what a red pin is known to break

summary: "A pin's validity and a pin's quality are two questions and the tooling
publishes one boolean for both. Owner's ruling 2026-09-01: a VALID pin is the
self-host fixedpoint and nothing else may block one; a pin is GRADED, never
gated. Emit two fields that cannot be confused — `pin_blocked: never` beside
`pin_grade: green | reds(N)` — recorded AT PIN TIME rather than re-derived from
a shifting archive, plus a MANIFEST of what a red pin is known to break. The
manifest is the part with the most value: had v398 said `known broken: C on
i386, arm32`, no B/E session would have built against it unaware for two days
and frankC's investigation would have been a lookup. Rollback prefers a green
pin and falls back to the most recent, so the recovery leg is never empty — it
has been empty since v354 on 2026-08-19."

## Why, in one measurement

`would_pin: false` has **zero deciding consumers**. `pin_shadow()`'s own
docstring says it *"deliberately never touches `pinned`, `make pin`, or
`stable_linux_amd64/**`"*. It is advisory and always was.

On 2026-09-01 **three sessions read it as a refusal** — frank-user, Track T on
seven, and the coordinator's earlier guidance. All three reasoned carefully.
That is the finding: this is not a reader defect, it is a wording defect, and
the fix belongs in the emitter. A verdict nobody is authorised to act on gets
read as authority anyway.

Cost: 19 days without a green pin, and v398 shipped a compiler that could not
build C for i386 or arm32 (fixed by `fc9c8ade2` the day AFTER the pin was cut),
which every `$(PXX_STABLE)` consumer carried.

## What to build

1. **`pin_blocked` is a constant `never`.** If it can ever read otherwise it is
   the same bug again. A flag that cannot come out false is not a guard — and
   neither is one that cannot come out true.
2. **`pin_grade`: `green` | `reds(N)`, decided AT PIN TIME** and written into
   the pin metadata beside `binsha`/`git`/`ts`. Not re-derived later: today
   three separate errors came from reading a shifting archive — a binary sha
   searched as a commit, a tstate bookkeeping commit read as a break point, and
   a `pin_baseline` carried from the OUTGOING pin answering a question about
   the incoming one.
3. **The manifest.** A red pin records WHICH jobs and, where known, which
   TARGETS it is broken for. A consumer asks "is my case affected", not "is the
   number zero".
4. **Rollback prefers green, falls back to most recent.** `pin_is_green` stays
   as the preference; an empty result must not mean an empty recovery.

## The positive control this needs

A grade that cannot come out `reds` on a red tree certifies nothing. Assert
both directions against real data: v398's tree (`c8e132a02b92`) must grade
`reds`, and a tree with a clean full tier must grade `green`. Drawn from the
pin population, not a synthetic fixture.

## Not in scope

Do not add a gate. The owner's ruling is in CLAUDE.md's per-lane pin section;
a change that makes any red block a pin contradicts it.
