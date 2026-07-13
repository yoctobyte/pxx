---
prio: 70
---

# regression: test-aarch64#src:test/test_cross_sysopen_family.pas red at a5fc06ee29b6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T05:54:30Z
- **Test source:** test/test_cross_sysopen_family.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_cross_sysopen_family.pas'` at a5fc06ee29b63a859c5a8f0ac17ad2e8435c7144

## Range
bad `a5fc06ee29b6`, last good `a5fc06ee29b6`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3463314/test_aarch64_sysopen_family  [code=74812B  data=176B  bss=9468B  procs=65]
ok: /tmp/testmgr-scratch-3463314/test_aarch64_sysopen_family_x64  [code=32928B  data=224B  bss=9468B  procs=65]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
