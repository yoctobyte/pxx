---
track: T
prio: 65
type: bug
status: backlog
found: 2026-09-04
found-by: claude-T
owner: ""
blocked-by: []
summary: "Every Makefile row that runs a cross-target binary spells it `\"$$(tools/run_target.sh <arch> $BIN)\"`, and a command substitution keeps stdout and throws the exit code away. Measured: 1082 of 1200 run_target.sh call sites are inside `$$( )`; 118 are bare. So a runner that cannot run is indistinguishable from a target that emitted nothing, and the comparison cannot fail for the right reason. This produced SEVEN auto-filed regressions on seven on 2026-09-04, all accusing the compiler, all caused by wasmtime not being installed. franka-29's RUNNER-ABSENT marker makes the message honest and leaves the mechanism intact."
---

# `run_target.sh`'s exit code is discarded at 1082 call sites

## The shape

```make
tools/expect_same.sh i386/test_npy_clone_i386 \
  "$$(tools/run_target.sh i386 $(TESTTMP)/test_npy_clone_i386)" \
  "$$(cat test/test_nilpy_thread_clone.expected)"
```

`"$$( … )"` captures stdout and **discards the exit status**. `run_target.sh`
exits 2 when the runner is missing and writes to stderr, which is correct and
unreachable: the substitution yields the empty string, `expect_same.sh` compares
empty against expected, and reports a content mismatch.

**A runner that could not run and a target that emitted nothing produce the same
red.**

## Measured, and much wider than first reported

| | count |
| --- | --- |
| `run_target.sh` mentions in `Makefile` | 1200 |
| **inside `$$( … )` — exit code discarded** | **1082** |
| called bare — exit code preserved | 118 |

The routing note that surfaced this carried "~57 rows" from another session.
That is low by roughly 19×; the population is 1082. Recording the discrepancy
rather than the smaller number, because a figure whose window is unstated reads
as a claim about everything — a mistake I made myself in
`chore-t-tools-devtest-00-is-six-reds-with-four-causes` and had corrected.

## What it cost, on one day, on one host

Seven regressions auto-filed on seven between 13:24Z and 15:56Z on 2026-09-04.
**Six of the seven were one missing binary** — `wasmtime` was not installed —
diagnosed and closed by franka-29 at `e80e685fc`. A seventh,
`done/regression-test-core-test-ansiterm-raw-write`, was outside that batch. All
of them accused the compiler.

`grep -rl 'wasmtime not found' devdocs/progress/tstate/reports/` → **14 reports**,
earliest `20260904T132406Z`. That is the earliest *seen*, not a start date: the
reports do not quote the recipe in a greppable form.

**Fixed on seven as of 2026-09-04**: wasmtime 48.0.1 installed to
`~/.local/bin/wasmtime`, the exact path `run_target.sh:128` looks for and the
exact version its comment at line 113 documents. Verified end to end — a wasm32
build through `tools/run_target.sh wasm32` returns `wasm-ok`, rc 0, empty stderr.
That removes today's *instance*. It does not touch the mechanism, and the next
absent runner on any host reproduces it.

## Why the marker fix does not close this

`e80e685fc` makes `run_target.sh` also print
`RUNNER-ABSENT: <tool> not found, so target '<arch>' was NOT RUN` on **stdout**,
through one helper, covering the qemu arms too, and still exits 2 so the row
stays red. It is a good fix with four controls and it makes the next ticket
honest — the marker now lands in the captured string, so a reader sees a cause
instead of an empty diff.

But it converts a silent wrong answer into a **loud** wrong answer. The
comparison still cannot fail for the right reason:

- the row is still red **because the content differs**, not because the runner
  did not run;
- any *future* runner failure that prints something plausible on stdout — a
  qemu that starts and dies, a wasmtime that warns and exits — lands as a
  content mismatch and accuses the target again;
- nothing asserts the precondition.

## The fix: assert the precondition, and BRANCH on it

This repo's own rule. Assert that the runner **ran** before comparing what it
printed, and branch — `&&` between stages, not `;`:

```make
	tools/run_target.sh i386 $(TESTTMP)/bin > $(TESTTMP)/bin.out && \
	tools/expect_same.sh i386/bin "$$(cat $(TESTTMP)/bin.out)" "$$(cat …)"
```

The rc now gates the comparison. 1082 rows is too many for one commit; convert
by target, and note the 118 bare call sites already have the property, so the
pattern exists in-tree.

## Positive control that costs nothing and would have caught all seven

One row per target whose runner is **deliberately absent**, asserted to produce
`RUNNER-ABSENT` and rc 2. Drawn from the real population, and its right answer
differs from the failure value — which is the property a control needs and the
reason a green suite hid this for a day.

## Same class, different path

`bug-t-a-backgrounded-tier-reports-the-wrappers-exit-code-over-the-tiers-verdict`
(8 sightings) — an exit code thrown away and a plausible verdict printed over it.
Also `bug-t-the-bench-tier-published-red-twice-with-zero-bench-rows-and-no-report`,
where the verdict *is* `Popen().returncode` and nothing survives to explain it.
Three paths, one class: **a true number about a different question.** Fixing any
one does not fix the others.
