---
track: T
prio: 50
type: bug
status: backlog
found: 2026-09-09
found-by: frank-coordinator
owner: ""
blocked-by: []
summary: "twatch auto-files a regression with `track: T` as a documented FALLBACK and tells the reader to re-lane it before working. Measured 2026-09-09 at 9945b2514: 12 of the 20 open regression tickets still carry it, aged 2026-09-02 through today, all at prio 70 — and `git log` over those files shows ZERO re-lanes ever, only the watcher's own `tstate-ticket(seven)` updates. Ran the queue rather than reasoning about it: 7 of the top 9 rows of `ready --track T` are these, above every real T tool ticket except two at prio 80; and the newest of them appears in neither `ready --track A` nor `--track P`. So the fallback puts a bug in front of the one lane whose own rule is `owns the TOOL, never the BUG`, and hides it from the lanes that could own it. NOT the same defect as bug-t-lane-attribution-has-two-instruments-that-disagree, which is about tickets with NO track field; here the field is present, deliberate and wrong."
---

# The auto-filed fallback lane routes every regression to the lane that may not own it

**The re-lane instruction is not a triage step.** The banner says *"This is a
FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it
before working it."* That is correct and it is also the whole difficulty:
deciding the lane requires diagnosing the cause, which is the work the ticket is
asking for. So the cheapest honest action for a T seat reading it is to decline
it — correctly — and the ticket stays where it is. Nobody is being careless; the
step that would move it costs the same as fixing it.

**Why it is invisible from any single seat.** A T seat sees a queue full of
tickets it correctly does not own. An A or P seat sees nothing at all. Only a
reader of every lane sees that these are the same tickets. That is also why this
was found by accident: frankS hit
`regression-test-core-test-generic-nested-inline-specialize` while proving an
unrelated Makefile row, and it is red at HEAD and green on the pin.

## Measured (9945b2514)

    open regression-* in ranked folders        20
    still at the track: T fallback             12
    oldest                                     2026-09-02  (7 days)
    all at prio                                70
    re-lanes by any agent, ever                 0
    top 9 of `ready --track T` that are these   7
    of those, visible in ready --track A / P    0

## What a fix has to decide, and why it is not a patch

**A better GUESS is the wrong direction** and the tool already says so: the
banner records that guessing a lane from the job's `src` is what *"sent three
reds in one job to the wrong lane"*. So do not make the filer smarter about
lanes.

Options, none of them costed here:

- **A** — file with no `track:` at all and let `ready` surface unlaned
  regressions in EVERY lane's queue. Honest about what is known; collides with
  `bug-t-lane-attribution-has-two-instruments-that-disagree`, which is about the
  ranker's fallbacks for exactly that state, so the two want deciding together.
- **B** — keep `track: T` but exclude auto-filed regressions from
  `ready --track T`'s ranked body and print them as a separate unlaned block,
  so T's queue stops being dominated by work T does not own.
- **C** — leave it and accept that regressions are found by the tstate report
  rather than by any `ready`. That is the status quo and it is a decision worth
  making explicitly rather than by default.

**Residual, and it belongs to nobody yet:** the specialize regression above is
red at HEAD, green on the pin, and `test-core` is not in `gate.sh quick`, so
nothing in the per-fix loop will surface it. frankS excluded their own two files
and frankH's `ad3f58463` by revert-and-rebuild, and measured the causal range as
**1603 commits touching `compiler/`** (the naive range back to the last commit
touching the test file is 10112 — the smaller number is the right population).
frankZ has been told and is in nested-specialize now.
