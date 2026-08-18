---
prio: 70
track: N
status: done
owner: frank2-7e
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:examples/tk/callbacks.npy red at 8f629af38632 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-17T21:49:03Z
- **Test source:** examples/tk/callbacks.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:examples/tk/callbacks.npy'` at 8f629af386321e43a837f6e76fbec995da30c3bf

## Range
bad `8f629af38632`, last good `eda43dea7629`, 214 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-793537/test_nilpy_tkcb26  [code=2510321B  data=76272B  bss=197364B  procs=1947]
  tk: tkinter_facade EXITED NONZERO under Xvfb
/usr/bin/xvfb-run: 200: /tmp/testmgr-scratch-793537/test_nilpy_tkinter26: not found

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Coordinator enrichment, 2026-08-17 overnight — NOT REPRODUCIBLE, and the code is identical

Track T's agent is down overnight, so this is the face-2 enrichment the stub is
missing. **Filed by the watcher, enriched here, not duplicated.**

**Measured at HEAD (`139a4a1f0`), same recipe the job runs:**

    ./compiler/pascal26 examples/tk/callbacks.npy <out>      -> ok, exit 0
    timeout 120 xvfb-run -a <out> > got 2>&1                 -> exit 0
    diff -u examples/tk/callbacks.expected got               -> IDENTICAL

**And the code is the same code.** Every commit between the accused sha
`8f629af38632` and HEAD is tstate, roster, digest or ticket prose — **zero
`compiler/` or `lib/` changes**. So nothing could have fixed it in between: the
tree that passes here is materially identical to the tree that failed there.

**The same sha reported both verdicts**, which is the decisive detail:

    db7e583cd  tstate(plexus): 8f629af38632 GREEN (native)
    474dc9293  tstate(plexus): 8f629af38632 RED  (full)   <- this stub

So the variable is the **run environment**, not the revision.

## Most likely cause, stated as unproven

The recipe is `timeout 120 xvfb-run -a <binary>` — a **GUI program under a virtual
X server with a 120s ceiling**, executed inside a 2700-job full tier on the
watcher's box. That is the most timeout-prone shape in the suite.

**Fourth timeout-shaped red on that box tonight**, and the others resolved the same
way: `crtl_exp2` is a recorded timeout, and `lib-test#117` / `test-nilpy#12` from
the v347 pin-verify both reproduce as *pass* under every relevant binary
(`bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label`). One
transient is noise; four in an evening on one host is a property of the host or the
tier's parallelism.

Deliberately **not** closed as flake. What would settle it:

- whether the run actually hit the 120s ceiling — the stub records a verdict, not a
  duration, so the one fact that separates "timed out" from "wrong output" is not in
  the record;
- whether `xvfb-run -a` display allocation contends when several GUI jobs run
  concurrently in the same tier;
- a re-run of the full tier on an idle box against this same sha.

**Note for the tooling ticket:** a RED whose failure mode is invisible from the
report is the same family as the positional job names — the record preserves the
verdict and discards the discriminator. A duration, or an explicit
`TIMEOUT`-vs-`DIFF` verdict, would have made this stub self-attributing instead of
needing a manual re-run.

### Do not read the third verdict as a re-run

`8f629af38632` carries **three** verdicts, and only two are about this job:

    db7e583cd  GREEN (native)
    474dc9293  RED   (full)    <- this stub
    85c0ba748  GREEN (slow)    <- NOT a re-run of anything here

The `slow` tier is **exactly one demoted shard** — `SLOW_SHARDS =
{"test-uforth": ("blocktest",)}` (`tools/testmgr.py:1561`), pulled out because it
was setting the wall time of every sweep. It never touches `test-nilpy`. Its
`fixed: []` is therefore not evidence that this job is still failing, and its
`GREEN` is not evidence that it recovered.

Recorded because the coordinator briefly read it as a confirming re-run before
checking the tier composition. A per-sha verdict list invites the assumption that
later verdicts supersede earlier ones; here they cover **disjoint job sets**, so
they cannot. Same shape as the rest of tonight's findings — a true statement about
the wrong subject.

### Root cause candidate identified — see the harness ticket

The recipe's `timeout 120` at `Makefile:363` is **hardcoded inside the make recipe**,
so it fires within make and reaches testmgr as an ordinary `fail`. Every part of
testmgr's contention machinery — `PEER_TIME_FACTOR` budget stretching, the co-tenant
retry rule, the `timeout` status itself — is structurally unable to see it. On a
loaded box testmgr stretches its own budgets while this ceiling stays rigid.

That is the mechanism this stub was groping at, and it is filed as
`bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic` (T, p55).
It also explains why six previously-closed timeout tickets did not stop the class:
all six fixed testmgr's OWN timeouts.

This stub stays open until either that fix lands or the job reds again with a
duration attached. **Still not closed as flake** — unproven.

### If a bisect result arrives for this, do not trust it

`twatch --status` shows this regression with **214 commits in range**. If the watcher
bisects it, the answer will be confidently wrong: a duration-driven failure converges
on whichever commit happened to straddle the budget, not on a first failure. That is
`bug-t-a-timeout-bisects-to-an-innocent-commit` (done, p45), which recorded the same
shape for `crtl_exp2` — the named commit touched nothing the job builds.

So a bisect verdict here is evidence about **load at the moment of each probe**, and
the job passing standalone at HEAD (measured above) outranks it. Whoever reads that
result tomorrow: check it against a standalone run before acting, and prefer fixing
the harness gap over chasing the named commit.

## The bisect converged — and my prediction about it was WRONG

Result: **`5215148bb` — "test(N): the tkinter facade's 2453 lines were gated on
'it still parses'"**, a one-commit range.

I predicted (above) that a bisect here would name an innocent commit, in the shape
`bug-t-a-timeout-bisects-to-an-innocent-commit` recorded for `crtl_exp2`. **That
prediction is falsified.** The named commit is not innocent and not arbitrary — it is
the most informative answer available.

What it did: the three tk `.npy` tests had been **compiled and never executed**, so
2453 lines of facade were gated on "it still parses". This commit added the
`.expected` files and eighteen Makefile lines that RUN them under Xvfb and diff the
output. Those eighteen lines contain:

    timeout 120 xvfb-run -a $(TESTTMP)/$$bin > $(TESTTMP)/$$src.got 2>&1

That is `Makefile:363` — **the exact line independently identified as the mechanism**
before the bisect finished. So the bisect and the static reading converge on the same
place by different routes.

**The bisect is right and "culprit" is the wrong word for what it found.** The commit
did not break the program. It introduced the *first execution* of it, and with the
execution came the fixed 120s ceiling that cannot participate in testmgr's contention
logic. Before it, the job could not fail this way because the job never ran anything.

So the correct reading is: **the test got stronger, and the new step is load-sensitive
in a way the harness cannot express.** Nothing here argues for reverting or altering
`5215148bb` — running those tests was plainly the right change, and the comment in it
("the comments above said 'run under Xvfb by hand', which means in practice never")
is a good catch on its own terms.

### What this does and does not settle

- **Settles:** the failure requires the *run* step, not compilation. Consistent with
  everything measured — the file compiles clean at HEAD and the accused sha differs
  from HEAD by prose only.
- **Does not settle:** timeout versus genuinely nondeterministic output. The HEAD
  measurement (exit 0, byte-identical against `callbacks.expected`) says the run
  passes uncontended, and the commit asserts output determinism was checked over
  repeated runs — but neither rules out a rare nondeterministic path. **A recorded
  duration would separate these**, which is precisely what the harness ticket asks
  for.

### Correction worth keeping

Two different failure modes were being conflated under "a timeout bisects badly":

1. **`crtl_exp2`'s shape** — the range spans commits that all run the job, the budget
   is straddled somewhere in the middle, and the bisect lands arbitrarily.
2. **This shape** — the range spans the commit where the job *started doing the
   expensive thing*, so the bisect lands on it exactly and correctly.

I applied (1) to a case that was (2), from the surface similarity of "long range,
timeout-ish red". That is the night's own recurring theme turned on me: a true
statement about the wrong subject. **A bisect result is not discredited by the
failure being duration-driven** — it depends on whether the duration-driven step
exists across the whole range.

## RESOLVED — and it is not a timeout. Measured, then reproduced deterministically.

*(frank2-7e, 2026-08-18, at `e252a17c7`.)*

The enrichment above converged — twice, by two routes — on `Makefile:363`'s
`timeout 120` as a load-sensitive ceiling. **That reading is falsified.** The
line is implicated, but not for its timeout.

### The measurement that separates the two

The whole enrichment asked for one fact the record discarded: a duration.

| | value |
| --- | --- |
| `callbacks` under `xvfb-run`, wall | **0.14 s** |
| `tkinter_facade` / `field_class_identity` | 0.24 s / 0.12 s |
| slowest of 20 consecutive runs | **120 ms** |
| the ceiling | 120 000 ms |

A ~1000x margin. No tier contention closes that. And 20/20 runs were
byte-identical against `callbacks.expected`, so the *other* arm of the open fork
— "timeout versus genuinely nondeterministic output" — is closed too: the output
is deterministic. Neither arm of the fork was the answer, which is why measuring
beat choosing between them.

### What the log tail actually said

The recorded failure was never a timeout, and it names its own cause:

```
/usr/bin/xvfb-run: 200: /tmp/testmgr-scratch-793537/test_nilpy_tkinter26: not found
```

A missing **binary**, and not even `callbacks` — `tkinter_facade`. A `timeout`
kill is rc 124 and silent. The discriminator was in the record after all; it was
read as timeout-shaped because the surrounding evidence was.

### Root cause: a producer/consumer edge invisible to the job splitter

`tools/testmgr.py split_jobs` cuts a recipe into independently-scheduled jobs and
keeps a producer with its consumer by union-find over **shared literal `/tmp`
paths**. The tk block RUNS three binaries but COMPILES one:

```
JOB test-nilpy#src:examples/tk/tkinter_facade.npy   -> /tmp/test_nilpy_tkinter26
JOB test-nilpy#src:examples/tk/field_class_identity.npy -> /tmp/test_nilpy_fldcls26
JOB test-nilpy#src:examples/tk/callbacks.npy       -> /tmp/test_nilpy_tkcb26
                                                      + the xvfb loop over ALL THREE
```

The loop reached its binaries as `$(TESTTMP)/$$bin` — built from a **shell
variable**. Dumping each job's `/tmp` tokens shows the consumer exposing exactly
one path, its own:

```
src:examples/tk/callbacks.npy   /tmp tokens: ['/tmp/test_nilpy_tkcb26']
```

No shared token, no merge, three unordered jobs — and the callbacks job runs
`test_nilpy_tkinter26` in a scratch dir where nothing ever built it.

**Reproduced deterministically** (fresh scratch, compile only `callbacks.npy`,
run the job's own loop) — identical to the report down to the compile stats:

```
ok: .../test_nilpy_tkcb26  [code=2510321B  data=76272B  bss=197364B  procs=1947]
  tk: tkinter_facade EXITED NONZERO under Xvfb
/usr/bin/xvfb-run: 184: .../test_nilpy_tkinter26: not found
```

So: 100% reproducible under job isolation, not a flake, not load-sensitive, and
green on a native tier only because some earlier job happened to leave the other
two binaries in the shared per-run scratch first.

### Fix (Track N — `Makefile`, the test-nilpy tk block)

Spell the three binaries by full path in the loop's item list, so the two paths
this job consumes appear literally in its own text. The existing union-find then
merges producers and consumer into one ordered job — verified: the merged job now
compiles all three binaries it runs. No `testmgr.py` change: the tool cannot
resolve shell variables in general, so the recipe stating its paths is the
normalising fix rather than a second mechanism.

Verified green in isolation (all three run and diff clean in a fresh scratch).

### Consequences for Track T

1. **The selector for this job CHANGES.** The merged job's first source is now
   `examples/tk/tkinter_facade.npy`, so `test-nilpy#src:examples/tk/callbacks.npy`
   — this ticket's repro line and the key twatch has red/green history under —
   **no longer selects anything**. Expect the old id to go silent and a new one
   to appear; that is this fix, not a disappearance.
2. **This is the third instance of one class**, and the splitter's own comments
   name the first two: a `.so` found by soname, and a bare-`/tmp`
   `LD_LIBRARY_PATH` consumer. Both got synthetic tokens. This one arrives
   through a *shell variable*, which the comment's phrase "invisible to a
   filename scan" already anticipates in spirit. A lint — flag any job whose text
   runs `$(TESTTMP)/$$<var>` or otherwise reaches /tmp through a variable — would
   catch the next one at authoring time. Filed as a suggestion for T, not done
   here (T owns the tool).
3. `bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic`
   (T, p55) is a **real and separate** gap — `timeout 120` inside a make recipe
   genuinely is invisible to testmgr's contention machinery. It is simply not
   what failed here. It should stand on its own evidence (`crtl_exp2`), with this
   job removed from its supporting set.

### Correction to the enrichment worth keeping

The bisect landed on `5215148bb` and the static reading landed on `Makefile:363`,
and their agreement was read as confirmation. Both were right about the *line*
and wrong about the *mechanism*: that commit introduced the first execution of
these tests, and with it both a 120 s ceiling **and** a three-binary dependency
expressed through a shell variable. Two candidate mechanisms arrived in one
commit; the convergence of two routes on the same line could not distinguish
them, and reading agreement as confirmation is what made the timeout look
settled. The duration was the cheap discriminator and it was one command away.
- 2026-08-18 — resolved, commit 9f11b405d.
