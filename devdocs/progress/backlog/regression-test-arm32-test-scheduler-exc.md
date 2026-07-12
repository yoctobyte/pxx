---
prio: 70
---

# regression: test-arm32#src:test/test_scheduler_exc.pas red at aaa58e72c1e8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T18:51:33Z
- **Test source:** test/test_scheduler_exc.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-arm32#src:test/test_scheduler_exc.pas'` at aaa58e72c1e8b7c2a4af9f33d89e4e6ea524027e

## Range
bad `aaa58e72c1e8`, last good `aaa58e72c1e8`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-458448/test_arm32_sexc  [code=173468B  data=432B  bss=38388B  procs=139]
ok: /tmp/testmgr-scratch-458448/test_arm32_sexc_x64  [code=50309B  data=456B  bss=46708B  procs=103]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
