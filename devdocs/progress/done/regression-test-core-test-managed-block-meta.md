---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_managed_block_meta.pas red at 86da0606d916 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-14T13:40:48Z
- **Test source:** test/test_managed_block_meta.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_managed_block_meta.pas'` at 86da0606d9167dbdef14eed8da5e104e5f5bd9d4

## Range
bad `86da0606d916`, last good `c0a49076d1d3`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-392706/test_managed_block_meta26  [code=91020B  data=3328B  bss=9668B  procs=198]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGED 2026-08-14 by Track T — consolidated into a Track A bug

Reproduced at HEAD with a rebuilt compiler: `FAIL grown ascii string stays ascii`.

Cause is `9ffbba0bd perf(A): append in place for \`s := s + x\``, which is
literally the construct the failing assertion exercises — and the test's own
comment names the hazard ("growth through the inline resize path must not lose
or invent the flag"). Filed as
[[bug-a-in-place-append-loses-the-ascii-kind-flag-on-growth]] (Track A, p75,
urgent — it is in pin v299, so every `$(PXX_STABLE)` lane has it).
- 2026-08-14 — resolved, commit 513de4f46.
