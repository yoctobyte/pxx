---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_errformat.npy red at 36d1bffda39d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T15:21:24Z
- **Test source:** test/test_cpyext_errformat.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_errformat.npy'` at 36d1bffda39d58099b403745c48b95cd8c1d7c58

## Range
bad `36d1bffda39d`, last good `0d8e7393a09c`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3177678/test_cpyext_errformat26: symbol lookup error: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26: undefined symbol: __pxx_PyErr_Message
(tail)
ok: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26  [code=2492974B  data=53456B  bss=33108B  procs=2333]
/tmp/testmgr-scratch-3177678/test_cpyext_errformat26: symbol lookup error: /tmp/testmgr-scratch-3177678/test_cpyext_errformat26: undefined symbol: __pxx_PyErr_Message

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
