---
track: T
prio: 85
type: feature
status: rejected
found: 2026-09-01
found-by: frank-user
---

# Grade a pin instead of gating it, and say what a red pin is known to break

summary: "A pin's validity and a pin's quality are two questions and the tooling
publishes one boolean for both. Owner's ruling 2026-09-01: a VALID pin is the
self-host fixedpoint and nothing else may block one; a pin is GRADED, never
gated. Emit two fields that cannot be confused — `pin_blocked: never` beside
`pin_grade: green | reds(N) | unmeasured` — recorded AT PIN TIME rather than re-derived from
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
2. **`pin_grade`: `green` | `reds(N)` | `unmeasured`, decided AT PIN TIME** and written into
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

## `unmeasured` is a THIRD grade, not a flavour of red

Added 2026-09-01 after Track T on seven caught the first draft collapsing two
different claims. **"Known broken" and "never measured" are not the same
thing**, and a `green | reds(N)` pair has nowhere to put the second.

This is the repo's own stated principle, and the first draft broke it.
`seed_baseline`'s docstring (`twatch.py:2597`):

> *"We did not measure it" must not be recorded as "we measured it and it was
> fine" -- that substitution is the defect class this whole gate exists to
> catch.*

A grade of `green` on an unjudged tree is exactly that substitution.

**The tool already makes this distinction and the first draft would have thrown
it away.** `trackt.py pinstatus` prints `NOT JUDGED at this sha` as its own
state, distinct from a verdict. Preserve it; do not invent it.

**Live instance, in v399 itself.** frankB's `4af4645ba` landed at 20:24:36Z --
a discarded managed function result had no owner, changing statement lowering
for EVERY Pascal program, with 979 of 1000 string handles previously leaking.
Verified: it IS in v399's tree, and there are **zero** full rows at that sha or
at the pin tree `86c71828c`; the three most recent full runs are all older.
Correctly smoke-gated per CLAUDE.md, so nobody did anything wrong -- which is
the point. This is normal operation, not an incident, and the manifest has to
represent it honestly.

**So the manifest carries two lists, never one.** Known-broken, and
never-measured-here. The second wants the COMMIT, because that is what makes it
cheap: "if `4af4645ba` misbehaves it is one commit and cheap to bisect to" is
actionable; "grade: reds(13)" is not.

## The positive control this needs

A grade that cannot come out `reds` on a red tree certifies nothing. Assert all
THREE directions against real data, drawn from the pin population and not a
synthetic fixture:

- v398's tree (`c8e132a02b92`) must grade `reds` -- it has a full row and it is RED.
- v399's tree (`86c71828c`) must grade `unmeasured` at pin time -- zero full rows,
  and `pinstatus` says `NOT JUDGED at this sha`. **This is the row that catches a
  grader defaulting an unjudged tree to `green`,** which is the whole reason the
  third grade exists.
- a tree with a clean full tier must grade `green`.

## Not in scope

Do not add a gate. The owner's ruling is in CLAUDE.md's per-lane pin section;
a change that makes any red block a pin contradicts it.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
