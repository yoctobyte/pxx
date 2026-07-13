---
prio: 70
---

# regression: test-c-conformance-aarch64#shard0/6 red at e530da678bc9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T11:45:39Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard0/6'` at e530da678bc93d2fbc4e153cfa7811102b425cb0

## Range
bad `e530da678bc9`, last good `e530da678bc9`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00187.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00187.c.expected	2026-07-07 21:11:07.000000000 +0200
    +++ /tmp/pxx_c_conformance.605161/out.txt	2026-07-13 13:42:22.667820627 +0200
    @@ -1,27 +1 @@
     hello
    -ch: 104 'h'
    -ch: 101 'e'
    -ch: 108 'l'
    -ch: 108 'l'
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00187.c(output)

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
