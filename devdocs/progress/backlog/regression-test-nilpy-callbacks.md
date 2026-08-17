---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:examples/tk/callbacks.npy red at 8f629af38632 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-17T21:49:03Z
- **Test source:** examples/tk/callbacks.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:examples/tk/callbacks.npy'` at 8f629af386321e43a837f6e76fbec995da30c3bf

## Range
bad `8f629af38632`, last good `eda43dea7629`, 214 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-793537/test_nilpy_tkcb26  [code=2510321B  data=76272B  bss=197364B  procs=1947]
  tk: tkinter_facade EXITED NONZERO under Xvfb
/usr/bin/xvfb-run: 200: /tmp/testmgr-scratch-793537/test_nilpy_tkinter26: not found

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
