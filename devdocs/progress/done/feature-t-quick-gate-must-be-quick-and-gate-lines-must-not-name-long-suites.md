---
summary: "`gate.sh quick` runs the 625s make test-nilpy, and ticket Gate: lines name long local suites — both push agents into running locally what Track T exists to offload"
type: feature
track: T
prio: 60
---

# Make the quick gate quick, and stop Gate: lines prescribing long local suites

- **Type:** feature (Track T + a cross-track convention) — **Track T**
- **Opened:** 2026-08-01. Filed from A+P+C+N after running exactly the wrong
  thing for the documented reason.

## Two halves; the second needs a decision

### 1. `gate.sh quick` is not quick (Track T, straightforward)

Measured 2026-08-01 on an idle box:

```
  PASS  make test-nilpy          (625s)
  PASS  self-host fixedpoint     (22s)
  PASS  testmgr --tier quick     (2s)
gate: GREEN
```

The "quick" gate spends **625 of its 649 seconds** in one suite. That is not a
quick gate; it is a full gate wearing the name of the fast one, and it is the
mode agents are told to reach for between edits.

CLAUDE.md's own rule is "confirm native, offload the matrix" — native confirm =
`testmgr --tier quick` + self-host fixedpoint, ≈40s. `gate.sh quick` should be
exactly that. The nilpy suite belongs in `gate.sh full` / Track T's matrix.

Ten minutes is also long enough to overlap another build, which is how it
collides with
[[feature-t-snapshot-compiler-binary-per-run]] and
[[bug-t-selfhost-build-uses-fixed-tmp-paths-colliding-across-clones]]. Shortening
it reduces the window those tickets are about.

### 2. Ticket `Gate:` lines prescribe long local suites (convention — decide first)

Nearly every N ticket's Gate line reads some form of:

> `make test-nilpy` + self-host byte-identical

So an agent following the ticket runs a 625s local suite, even though T covers
it and the project's stated model is to offload it. This is not agents ignoring
guidance — it is two pieces of guidance disagreeing, and the ticket is the one
in front of you at the time. I ran the 625s suite this session for precisely
this reason.

Proposed convention:

> **Gate:** `testmgr --tier quick` + self-host byte-identical locally; the
> suite (`make test-nilpy`) via Track T after push.

This changes what every track does before pushing, so it is a **Track U call,
not Track T's to make unilaterally** — if that reading is right, split this half
into `decide-gate-line-convention` rather than landing it here. The tradeoff to
weigh: pushing on a 40s confirm means master can carry a suite-level red for the
minutes until T reports, which CLAUDE.md already accepts ("master MAY carry
cross-target reds for hours — tstate is the truth"), but Gate lines were written
before that was the model.

Half 1 can land without waiting for half 2.

## Gate

`gate.sh quick` completes in well under a minute on an idle box and still
catches a deliberately broken compiler change. `gate.sh full` still runs the
suites.

## 2026-08-01 (same day) — correction: gate.sh is the PIN gate, not the dev gate

Written above on a wrong premise. Corrected on the spot: **`tools/gate.sh` is
for pinning.** So "gate.sh quick spends 625s in one suite" is not a bug in a
fast gate — it is a heavyweight gate being reached for in a loop it was never
meant for. Half 1 above should be re-read as: *stop routing the dev loop through
gate.sh at all*, rather than *make gate.sh quick faster*.

What actually changes:

- **Dev loop** = `make compiler/pascal26` + run your repro. Measured today: one
  self-compile 5.74s, so build+verify ≈ 12s — and that build ALREADY IS the
  byte-identical self-host fixedpoint (the `$(COMPILER)` rule compiles twice and
  `cmp`s, failing after 4 rounds). There is nothing to skip and nothing to add.
- **gate.sh** = the pin gate, correctly heavy, and moving into testmgr per
  [[feature-t-testmgr-owns-pinning-interruptible]].
- **Breadth** = Track T, consumed via [[feature-t-agent-side-tstate-watch]].

The doc fix matters more than the tooling fix here: CLAUDE.md's *"Run the gate
with `tools/gate.sh` (quick | lib | full | check), and background THAT"* reads as
the everyday instruction, and that line plus the `Gate:` lines on tickets are
what pulled an agent into two 554s runs in one session. Half 2 (the Gate:-line
convention, [[decide-gate-line-convention]]) is unaffected and still the Track U
call.

---

## HALF 1 DONE — `ed7b401b8` (claude@xeon, 2026-08-01)

`gate.sh quick` is now self-host fixedpoint + `testmgr --tier quick`.
`make test-nilpy` moved to `full`.

```
  PASS  self-host fixedpoint  (49s)
  PASS  testmgr --tier quick  (9s)
gate: GREEN                    58s total     (was 649s)
```

Measured with the watcher running concurrently on the same box — load 16.2, and
`gate.sh` itself warns that makes things 2-3x slower. On an idle box this is the
~30s the ticket asked for.

### Why it is safe NOW and would not have been this morning

Dropping the suite from the fast path only became honest once the fast path
could still see NilPy at all:

1. `testmgr --tier quick` now carries dense **NilPy and C canaries**
   ([[feature-t-quick-canary-for-nilpy-and-c]]) — a gross NilPy break is still
   caught here, in ~1s, with per-section lines.
2. The whole `test-nilpy` suite is enrolled in Track T's limited/full matrix
   ([[bug-t-xeon-job-set-covers-only-a-third-of-nilpy-tests]]) — it is not
   skipped, it is **offloaded**, which is the entire point.

Before those two landed, removing it would have created a real hole. Order
mattered.

### Side effect the ticket predicted

> Ten minutes is also long enough to overlap another build

58s of gate is a much smaller window for a concurrent rebuild than 649s, so this
also shrinks the exposure that
[[feature-t-snapshot-compiler-binary-per-run]] and
[[bug-t-selfhost-build-uses-fixed-tmp-paths-colliding-across-clones]] address —
both of which are now landed as well, so that class is closed from three sides.

### Half 2 deliberately NOT done

Ticket `Gate:` lines prescribing long local suites changes what **every** track
does before pushing. You called it a Track U decision and I agree — it is filed
as [[decide-gate-line-convention]] and is not Track T's to make unilaterally.
`gate.sh check` now prints the new composition, so at least the tool no longer
advertises the old one.

## Log
- 2026-08-01 — resolved, commit ed7b401b8.
