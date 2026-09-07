---
slug: bug-t-the-tmp-sweep-guards-against-reaping-its-own-scratch-and-not-a-foreign-live-runs
title: The /tmp sweep guards against reaping its OWN scratch, not a co-tenant's live one
type: bug
track: T
prio: 45
status: open
owner:
---

## Summary

**We wrote this failure down and then spent two hours rediscovering it from the
outside.** `reap_stale`'s docstring, one function above the sweep, describes it
exactly:

> a job that reports `ok: <path> [code=...]` for an artifact and then `ld:
> cannot find <same path>` a few steps later — no error from the compiler, no
> error from the reaper, a red in whatever subject happened to own the file.

Nothing points at that paragraph from the failure, so it cost what a warning
costs when it is not attached to the thing that trips it. **Leading with it
because the next person to meet this will also meet it from the outside.**

The defect: `sweep_orphan_tmp()` decides by PID LIVENESS and deletes with
`shutil.rmtree(p, ignore_errors=True)`. It correctly skips `pid ==
os.getpid()`. **It has no defence against a FOREIGN run whose naming pid is
dead while its orphaned jobs are still writing.**

## Why it is reachable

- **Two testmgr runs on one box is the DESIGNED normal state, not an anomaly.**
  `foreign_runs()` says so: *"the watcher daemon's dedicated clone versus a dev
  checkout"*. The per-repo lock is per-CLONE and cannot see across them; the
  `/tmp` sweep is global across all of them.
- **Orphans outlive their testmgr.** `twatch.kill_child()` escalates SIGINT then
  SIGKILL. testmgr kills its own job process groups on SIGINT and cannot on
  SIGKILL, so a hard kill leaves compiler jobs running with a dead parent.
- **twatch has an orphan incident on record.** `_kill_orphan_gate` exists because
  on 2026-08-12 a cycle threw and left a full-tier testmgr running unattended.

Put together: testmgr P is SIGKILLed, its jobs survive as orphans still writing
into `$TESTTMP/testmgr-scratch-P`, a co-tenant testmgr starts, finds P dead, and
rmtrees the tree under them. `sweep_orphan_tmp()` runs at entry
(testmgr.py:6328, *"reclaim dead runs' scratch first"*), before this run's own
scratch exists and independently of any lock.

## What it looks like downstream

`pascal26: error: compiled successfully but wrote no output file: <path>` — the
code was generated and the parent directory is gone. **Reproduced both shapes
locally:** a missing parent and an output path occupied by a directory each
produce that error, character-identical.

The reading it invites is a compiler regression, because the error names the
compiler and arrives on whatever commit is on top. It cost this fleet roughly
two hours on 2026-09-07 (five native NEW-REDs on seven, all
`src:compiler/compiler.pas`, blamed on a codegen change that in fact makes that
artefact 31.9% SMALLER).

## The asymmetry that makes it a box property

CLAUDE.md:785 — **T runs on seven and plexus deliberately does not.** A
single-testmgr box's sweep can only ever see its own live pid and has nothing to
delete. This predicts, with no reference to the tree: reproduces on seven, does
not reproduce on plexus at the same sha, indifferent to which commit is on top.
All three hold.

## Not established

That this fired on seven on 2026-09-07. The mechanism is proven reachable from
code and the symptom matches; nobody has read seven's process table for the
window. **A negative `ls -ld` on the artefact paths does NOT clear it** —
`rmtree` on the scratch root removes the artefact path too, so ENOENT is what
both this and an ordinary cleanup leave behind (frankS's point).

## The fix is not "check the pid harder"

The sibling paths converged on `pid in (os.getpid(), os.getppid())`, which
protects SELF. Nothing protects a co-tenant, and a pid cannot: `lock_state()`
already records that *"pids get reused"*. Options worth costing:

1. **A liveness file the OWNER touches** — sweep on heartbeat age, not on pid
   existence. Fails in the safe direction: a stale heartbeat means the run
   really is gone.
2. **Never sweep a foreign scratch at all.** `foreign_runs()` already
   distinguishes them; leave co-tenants to their own atexit and to the 6h
   tmpfiles ageing.
3. **An advisory lock on the scratch root** held for its lifetime, so a live
   directory is unreapable by construction.

(2) is the smallest and gives up only disk that the OS reaper already collects.

## Related

`tools/testmgr_reap_self_devtest.py` is the positive control for `reap_stale`'s
self-guard. There is no equivalent for the co-tenant case, and a devtest for it
needs two pids, so it wants a real fixture rather than an assertion.
