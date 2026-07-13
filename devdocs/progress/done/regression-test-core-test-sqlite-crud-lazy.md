---
prio: 70
---

# regression: test-core#src:test/test_sqlite_crud_lazy.pas red at f913bd22ae30 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T06:32:37Z
- **Test source:** test/test_sqlite_crud_lazy.pas test/test_lazy_var_scope_fail.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sqlite_crud_lazy.pas'` at f913bd22ae30f30cc3c461260777cf12a110c50c

## Range
bad `f913bd22ae30`, last good `8ffa3414f473`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3685081/test_sqlite_crud_lazy26  [code=49866B  data=1616B  bss=9712B  procs=580]
Segmentation fault (core dumped)

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
