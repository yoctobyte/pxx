---
prio: 70
---

# regression: test-core#676 red at 51f2a8a3258f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T13:28:49Z
- **Test source:** test/test_c_gtk_types.pas

## Repro
`tools/testmgr.py --tier full --job 'test-core#676'` at 51f2a8a3258fd4b06d070a5136bb07487d63d2ae

## Range
bad `51f2a8a3258f`, last good `51f2a8a3258f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1445796/test_c_gtk_types26  [code=43020B  data=708B  bss=8924B  procs=13618]
xvfb-run: error: Xvfb failed to start

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
