---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_bytes_decode.npy red at 74a925112afc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-01T21:05:27Z
- **Test source:** test/test_nilpy_bytes_decode.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_bytes_decode.npy'` at 74a925112afc049f24fe9ef3ec588f6425ef8d86

## Range
bad `74a925112afc`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:23: error: no overload of bytes matches these arguments
  argument types: (class)
  candidates:
    bytes(class)
    bytes(AnsiString)
  near:       >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
