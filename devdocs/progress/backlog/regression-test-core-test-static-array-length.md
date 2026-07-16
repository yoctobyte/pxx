---
prio: 70
---

# regression: test-core#src:test/test_static_array_length.pas red at fb9346bd4bce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-16T17:53:40Z
- **Test source:** test/test_static_array_length.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_static_array_length.pas'` at fb9346bd4bce1bef522968ffe0c212f99880b693

## Range
bad `fb9346bd4bce`, last good `5df694cf966e`, 11 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-614199/test_static_array_length26  [code=37001B  data=944B  bss=9660B  procs=79]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
