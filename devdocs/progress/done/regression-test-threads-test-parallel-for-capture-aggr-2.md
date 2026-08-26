---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_parallel_for_capture_aggr.pas red at 70f6a360f475 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T13:08:43Z
- **Test source:** test/test_parallel_for_capture_aggr.pas

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_parallel_for_capture_aggr.pas'` at 70f6a360f47529f3a61454e92331d3138b1a9c4d

## Range
bad `70f6a360f475`, last good `357217a73608`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-2325321/test_parallel_for_capture_aggr26  [code=127424B  data=3744B  bss=42600B  procs=269]
Segmentation fault

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution — 2026-08-26

Fixed. Root cause and full write-up: [[bug-a-the-parallel-for-worker-still-builds-the-old-dynarray-accessor]].

The `parallel for` worker still synthesized the pre-`@dy` dynamic-array capture accessor, so `capj^[i]` read the array's first ELEMENT as a handle. Verified GREEN on all four tiers: test-threads via `testmgr --tier native --job`, and i386 / arm32 / aarch64 via `tools/run_target.sh` — all PARFORAGGR OK.

This stub and its siblings are ONE defect each seen from a different tier —
`progress.sh dupes` scores the two `parallel_for_capture_aggr` stubs at 82%
against each other, which is the first thing that command found when it was
built (bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance).
Kept as separate rows only because the watcher files per failing JOB; they close
together because they were always one bug.
- 2026-08-26 — resolved, commit cd5d54964.
