---
track: T
prio: 45
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "The csmith campaign cites findings by SEED. A seed only reproduces the same program against an identical generator version AND identical --csmith-args, so a later `seed N passes` is equally consistent with `fixed` and with `today's csmith emits a different program`. Three named open findings (901, 1502, 5004) now pass at HEAD and NONE of them can be closed on that evidence."
---

# A fuzz finding cited by seed alone cannot prove a fix

- **Track T** — fuzzing tooling and its report format (`tools/csmith_fuzz.py`,
  and the same shape in `tools/fuzz.sh` / `tools/pasmith*.py` wherever a finding
  is recorded by seed).
- **Found:** 2026-08-30 by frankC, running the csmith campaign — from **three
  independent instances**, not one.
- **Record-keeping, not a compiler change.** Nothing here is a codegen defect.

## The measurement

`feature-c-csmith-differential-fuzzing` names three open findings by seed. All
three now pass:

| seed | filed | status at HEAD `f2bfbb3c94a5` |
| ---: | --- | --- |
| 901 | 2026-07-13, "unreduced crasher" | passes (frankC, 2026-08-29) |
| 1502 | 2026-07-13, "unreduced crasher" | passes (frankC, 2026-08-29) |
| 5004 | 2026-07-18, `PXX_COMPILE_FAIL`, kind-5 `AN_BINOP` | **passes (2026-08-30)** |

**None of the three can be closed on that evidence**, and that is the defect.

## Why a passing seed proves nothing

The campaign ticket already knows half of this — it carries the trap in its own
Traps section:

> **Replaying a seed without the same `--csmith-args` generates a DIFFERENT
> program.** Use the saved `t.c` in the findings directory, not just the seed.

The half it does not say is that **the generator version is part of the same
contract.** csmith is a program; its output for a given seed is a function of
its version as much as of its flags. This box has **csmith 2.3.0, git
`30dccd7`**. Nothing anywhere records which csmith produced the July findings.

And the escape the trap names is gone: *"the saved `t.c` in the findings
directory"* was written to a session scratchpad under `/tmp`, and the ticket's
own text says *"`/tmp` findings are gone by now"*. So for all three findings the
only surviving identifier is the one that cannot carry the proof.

The result is a verdict that reads as good news and is not evidence:

```
seed 5004: ok   ->  "the AN_BINOP lowering gap is fixed"        (maybe)
                ->  "today's csmith emits a different program"  (equally consistent)
```

The error class itself still exists as a general fallback (`ir.inc:617`), so its
absence here is about **reachability**, not removal.

## Why this is a defect in the format, not bad luck

Three for three. Every finding this campaign has ever parked was cited the same
way, and every one of them has become unverifiable by the same mechanism. It
will recur on the next finding, and the one after, because nothing in the record
format changes when a fix lands or when csmith is upgraded.

It is also the day's recurring shape in a new place: **a check that reports
success without having asked the question.** Compare
`task-t-the-c-corpus-is-two-rungs-not-four-and-a-missing-tree-reports-pass`,
where a rung self-skips `exit 0`. Here a *replay* answers a question about a
program it may never have compiled.

## What would fix it

A finding's record must be **self-sufficient** — reproducible without the
generator agreeing to behave the same way twice:

1. **Commit the generated `t.c`** with the finding, not the seed alone. It is the
   only artefact that is definitionally the program that failed. Size is not an
   objection at the rate findings are filed; if it is, gzip it.
2. **Record `csmith --version` output** (version *and* git hash — 2.3.0 alone is
   not enough, the package carries `30dccd7`) alongside the seed and the exact
   `--csmith-args`.
3. **Emit all three into the finding's `REPRO.md`** so a ticket citing the
   finding cites a directory rather than a number.
4. Consider making the harness **refuse to write a finding** it cannot make
   self-sufficient — the same discipline as reporting skips separately from
   passes, which this harness already gets right.

Point 1 is the load-bearing one; 2-3 are what let a stale record be *recognised*
as stale rather than silently believed.

## What this does NOT ask for

Not a re-run of the three stale findings to "settle" them — they cannot be
settled, and pretending otherwise is the error this ticket describes. Mark them
**unverifiable, cause: citation format**, and let the next batch find the class
again if it is still there. A finding that has to be rediscovered is cheaper than
a fix credited to a compiler that may never have earned it.
