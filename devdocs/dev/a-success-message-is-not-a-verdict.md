# A success message is not a verdict

**One rule:** for any long job, **do not accept an exit code as its verdict.
Require the job's own terminal line** — `converged after N round(s)`,
`gate: GREEN`, `N/N pass`, `STABLE vN OK`. **Absence of that line is the tell,
and there is never an error to wait for.**

This doc exists because the same failure arrived four times in four days, in four
different mechanisms, and each time the success path was *entirely truthful* about
its own narrow claim. Nobody was careless. The reports were correct and the
readings were wrong, because a green whose scope nobody states is read at the width
of its name.

## The four

| # | what reported success | what had actually happened |
| --- | --- | --- |
| 1 | `make compiler/pascal26` printing `up to date`, exit 0 | **nothing was built.** In a tree seeded with a copied-in binary, `cp` stamps the seed newer than the sources, so make no-ops. No fixedpoint was proved and nothing said so. |
| 2 | `twatch`'s `verify_pin` entering its phase | **7 attempts, 7 preemptions, 0 completions.** It had no commitment point, so it could be entered and never finish — consuming the idle slot breadth needed, while the pin stayed unjudged. |
| 3 | the watcher daemon restarting cleanly | **it was serving stale code.** The clone is detached at the sha under test, so `git pull` fails *by construction*; a restart reloads from the clone, not origin. Daemon up, healthy, publishing — running the old binary. |
| 4 | a background task notification: **"completed (exit code 0)"** | **the build had been killed.** The log ends `make: *** [cross-bootstrap-aarch64] Terminated`. The 0 came from the backgrounding wrapper, not from make. |

Instance 4 is the one that generalises hardest, and frankA's own note on it is the
reason this doc exists:

> I only knew better because I was the one who killed it — had it died to OOM at
> 4.1 GB RSS, or a reboot, the notification would have been the entire signal and
> it said PASS.

**A verdict you can only distrust because you happen to know the cause is not a
verdict.** Every one of these four is silent in exactly the situation where you
have no side knowledge, which is the situation the verdict exists for.

## Why exit codes fail here specifically

An exit code is a claim by *whatever process the shell last waited on*. For a long
job that is routinely not the job:

- a **wrapper** (backgrounding, `timeout`, a shell pipeline) reports its own status,
  not the command's — `cmd | tail; echo $?` is `tail`'s status, and that has
  produced a wrong conclusion here too;
- a **no-op** is a legitimate success — make exiting 0 because it had nothing to do
  is make working correctly;
- a **partial run** that was killed mid-way has no distinguished status of its own.

The job's terminal line does not have these failure modes, because the job only
prints it after doing the work.

## The companion rule: pin the SOURCES, not just the binary

The standing rule is *hunt async, verify against a known sha* — any measurement or
verdict must name the sha of the binary it came from. **That is not sufficient for
a long verification, and the gap cost an hour of the contended box on 2026-08-29.**

An aarch64 stage-2 fixedpoint reads `compiler.pas` and its ~200 includes **lazily
from the working tree, over an hour**. Two unrelated fixes landed meanwhile, and a
`sync.sh` rebase rewrote every file in `compiler/` mid-run. The binary being built
came from an unknown mix of sources and **cannot be attributed to any sha**.

frankA threw the run away rather than report it, which was right:

> A fixedpoint verdict whose inputs mutated underneath it is not a weak result; it
> is **not a result**, because it would have reported identical-or-differing with
> equal confidence either way.

**So: a long verification must read from a checkout that cannot change under it** —
a detached clone at the sha, or a snapshot copy. Not the tree you are working in.
This is why Track T's watcher runs in its own clone, and the same reasoning applies
to any lane running an hour-long cross-target check.

## What to do

- **Read the job's terminal line.** If you cannot name the line that says it
  finished, you do not have a result.
- **Never report a number, a verdict, or a "still broken" without naming the sha
  of the binary it came from** — and for a long run, the sha of the *sources* too.
- **Run long verifications against an immutable checkout.** If the tree can be
  rebased under the run, the run is not attributable.
- **Do not muzzle a tool you are testing.** `2>/dev/null` and pipelines have twice
  turned a loud failure into an empty output that read as "nothing to report".
- **When a workaround is installed while a bug is open, it becomes a blindfold the
  moment the bug is closed** — `scheduler.pas` calling `exit_group` directly means
  `test_sched_reactor_exhaustion` would pass with the `Halt` bug still present.

## The waiting side: a poller's vocabulary is a claim too

Every instance above is about a process *emitting* the wrong signal. The mirror
image is a process *listening* for the wrong set, and it fails silently rather
than loudly — so it is harder to notice and it costs wall-clock instead of
correctness.

Measured 2026-08-29. Two background waiters sat on the aarch64 cross-bootstrap:

```sh
until grep -q "byte-identical\|differ\|Error\|error:" "$log"; do sleep 30; done
```

Four patterns, chosen to cover "it worked" and "it failed". The run's actual
terminal line was:

```
make: *** [Makefile:12504: cross-bootstrap-aarch64] Terminated
```

which matches **none of them**. Both waiters would have polled forever — and did
for 52 minutes — over a job that was already over. The same hole swallows
`Killed` (OOM), `Segmentation fault`, `No space left on device`, and a bare
non-zero exit with no message at all.

The bug is not the missing pattern; adding `Terminated` to the list just moves
the hole. It is that **the waiter enumerated OUTCOMES it could imagine instead of
watching for the one thing that is always true: the process ended.** An outcome
list is open-ended and a liveness check is not.

- **Wait on liveness, then read the result.** `wait $pid`, or poll
  `kill -0 $pid` / the task's completion, and only *then* grep the log for which
  outcome it was. The two questions are "is it over?" and "what happened?", and
  conflating them is what hangs.
- **Every unbounded `until` wants a deadline.** A waiter with no timeout cannot
  distinguish "still working" from "will never finish", which is instance 2 in
  the table above wearing the poller's hat.
- **A poller that has learned nothing for N cycles should say so.** Silence from
  a waiter reads as patience; it is equally consistent with the thing it watches
  having died before it started.

## The sibling: an empty population

This doc is about a green whose **scope** nobody states. Its sibling is a green
whose **population is empty** — a guard asserting a negative passes just as
readily when there is nothing to check as when the property holds, and prints the
same word either way. The audit that finds those, and the rule for disposing of
what it turns up, is **`the-empty-tree-audit.md`**.

## Where the instances are recorded

Faces 31, 45, 46 and the MAX_CODE ticket's own notes, in
`devdocs/progress/backlog/feature-a-a-refusal-is-a-claim-with-a-date-on-it.md`.
That file is the running index; this doc is the one rule they share.
