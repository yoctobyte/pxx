---
prio: 70
---

> **origin/master has advanced 17 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_avx.pas red at 05f21c126295 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-14T17:13:56Z
- **Test source:** test/test_asm_avx.pas

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_avx.pas'` at 05f21c126295cdf685ac857dfd8432e104149bf1

## Range
bad `05f21c126295`, last good `dfbe25026dae`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-645599/test_asm_avx26  [code=55192B  data=1976B  bss=9604B  procs=112]
Illegal instruction (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
