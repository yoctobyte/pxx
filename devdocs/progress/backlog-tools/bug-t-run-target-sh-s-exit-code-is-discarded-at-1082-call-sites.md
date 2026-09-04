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

## 2026-09-04 — the INVERSE arm, and the number that should set this ticket's prio

Not my ticket; adding a measurement rather than re-laning it. Raised by
frankb-78 from the other direction and routed here by frankuser; the count below
is mine and was run against the Makefile at `8dacaaa15`.

**The body above documents the benign half.** *"A runner that could not run and
a target that emitted nothing produce the same red"* holds **only because
`expected` is non-empty**. Invert it: **a row whose expected output is itself
empty compares empty against empty and PASSES.** The runner never ran, the exit
code was discarded, the comparison succeeded, and the tier says green. Nothing
in the harness observes it — not the rc, not the diff, not the verdict. That arm
files nothing, because there is nothing to file.

**So the count that decides the prio is not 1082.** It is: of those, how many
have an empty or whitespace-only expected? The other ~1063 are noisy and
self-reporting; only this subset is silently green.

### Measured, and the answer is currently zero

Over every Makefile line naming `run_target.sh` (1202 lines at `8dacaaa15`;
line count, not call-site count, so it does not contradict the 1082 above):

| | |
| --- | --- |
| expected is a **literal** empty or whitespace-only string | **0** |
| expected is `$$(cat <file>)` where that file is empty | **0** (42 distinct files, none empty) |
| expected is `printf ''` | **0** |
| rows with no `expect_same.sh` at all | 80 — and these are the SAFE ones: they either capture `rc=$$?` explicitly, hand the command to `assert_no_leak.sh` as arguments, or run bare so make checks the status itself |

**So the silent-green population is empty today, and the hazard is latent rather
than live.** That is an argument about the prio, not about the finding: nothing
stops the next row from having an empty expected, and when one appears there is
no instrument that will say so. frankb-78's verdict on its own rows is the right
way to say it — *"my rows are safe, by the comparison rather than by the rc"* —
protection by coincidence of the expected data.

### The positive control this ticket should carry

Per the repo's own rule — *if the machinery did nothing at all, would this row
still pass?* — a row with an empty expected answers **yes**. The control is
therefore a row with an empty expected and its runner deliberately absent,
asserted to FAIL. It fails today for zero rows because zero rows have that
shape, so the control has to be **constructed**, and constructing it is the
cheap way to prove the mechanism rather than the population.
