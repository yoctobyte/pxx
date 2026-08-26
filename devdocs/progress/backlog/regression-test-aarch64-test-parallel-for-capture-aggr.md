---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_parallel_for_capture_aggr.pas red at 70f6a360f475 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T13:28:14Z
- **Test source:** test/test_parallel_for_capture_aggr.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_parallel_for_capture_aggr.pas'` at 70f6a360f47529f3a61454e92331d3138b1a9c4d

## Range
bad `70f6a360f475`, last good `902e53050f07`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-2339895/test_aarch64_parcapaggr  [code=295488B  data=3696B  bss=42464B  procs=269]
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
Segmentation fault

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
