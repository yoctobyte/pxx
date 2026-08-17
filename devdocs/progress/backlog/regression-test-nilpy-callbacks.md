---
prio: 70
track: N
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
