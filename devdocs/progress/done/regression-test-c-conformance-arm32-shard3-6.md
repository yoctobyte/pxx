---
prio: 70
---

# regression: test-c-conformance-arm32#shard3/6 red at e6844ff49085 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T07:58:31Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-arm32#shard3/6'` at e6844ff49085d4d0f87d4266976df7934549c7b5

## Range
bad `e6844ff49085`, last good `e6844ff49085`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00040.c — exit code 124 (want 0)
test-c-conformance-arm32: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-arm32: FAILURES: 00040.c(exit=124)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage 2026-07-13 (Track A) — green, closing

Green at HEAD on the exact repro job, and Track T's own watcher reports full-tier GREEN at
bc5f77d7 (`tstate/`, commit 7f8bd81f), which explicitly lists the aarch64 jobs as FIXED.

The two c-conformance stubs carry the 0-commit range signature (`bad` == `last good`), the
same harness-flake shape as regression-test-aarch64-test-cross-sysopen-family. The aarch64
C-conformance shard, though, was genuinely repaired by ab568c7c (frozen inline strings on
the cross backends) — the watcher marked shard3/6 FIXED at the commit that landed it, so
these shards were likely the same root cause rather than flakes. Either way they pass now.
