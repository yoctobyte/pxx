---
track: C
prio: 50
type: bug
blocked-by: []
summary: "test/quickjs/runner.c segfaults with ZERO output on the full smoke.js, and does so identically when built with the PINNED compiler — so it is not a HEAD regression. Small evals work on both. Observed 2026-08-20 in passing while landing the C entry-stub init phase; NOT caused by it, and filed separately so it is not attributed there."
---

# `test/quickjs/runner.c` segfaults with zero output on the full `smoke.js`

- **Track C** — the quickjs corpus target.
- **Observed** 2026-08-20 by frank2 while landing
  [[feature-c-entry-stub-must-run-initializers-for-environ]]. **Not caused by it** — see the
  control below. Filed as its own ticket precisely so it is never attributed to that change.

## What was seen

Running the full `smoke.js` through `test/quickjs/runner.c` **segfaults with zero output**.
Small evals work.

## The control, and it is the part that makes this filable

**The same failure reproduces when the runner is built with the PINNED compiler** — empty
output from both, small evals working on both. So it is pre-existing or environmental, and
in particular it is **not** a regression introduced at HEAD.

That control is what separates "a defect we own" from "a defect this week's work caused",
and it was run before reporting rather than after being challenged. Note the shape: building
with `PXX_STABLE` **removes the variable** rather than arguing about it — see
[[feedback_control_must_actually_remove_the_variable]].

## What is NOT yet known

Deliberately left open rather than guessed, because nothing here has been measured:

- Whether it is a pxx defect at all, or environmental on this box.
- Whether it is a stack-depth / recursion issue in the runner, a codegen defect, or a crtl
  gap that `smoke.js` reaches and small evals do not.
- Which construct in `smoke.js` first triggers it. **Bisecting the INPUT** — feed progressively
  larger prefixes of `smoke.js` — is the cheap first move and needs no compiler work.

**Zero output with a segfault is itself a clue**: it suggests the crash lands before any
buffered stdout is flushed, which points earlier than the first `print` rather than at
whatever statement is "last" in the file. Do not assume the failing construct is near the end.

## First moves

1. Prefix-bisect `smoke.js` to find the smallest input that crashes.
2. `-g -O2` + gdb (`source tools/pxx-gdb.py`) on the reduced case; the rbp chain answers
   whether it is a runaway recursion or a wild pointer. See
   [[project_debug_toolkit_playbook]].
3. Only then decide the lane: a codegen or IR fault routes to **Track A**, a crtl gap stays
   **C**, an environmental cause gets recorded and closed.

## Gate

The reduced case runs; `smoke.js` produces output. C tests green + self-host byte-identical.
