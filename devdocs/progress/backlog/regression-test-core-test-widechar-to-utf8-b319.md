---
prio: 70
---

# regression: test-core#src:test/test_widechar_to_utf8_b319.pas red at d94db8d6b0cc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T21:19:49Z
- **Test source:** test/test_widechar_to_utf8_b319.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_widechar_to_utf8_b319.pas'` at d94db8d6b0ccc8a1ce8441e7104293aeff071199

## Range
bad `d94db8d6b0cc`, last good `9daabff94650`, 16 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2631929/test_widechar_utf8_b31926  [code=51222B  data=592B  bss=9472B  procs=98]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
