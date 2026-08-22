---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_classref.pas red at 392ea5d94545 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T10:38:10Z
- **Test source:** test/test_classref.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_classref.pas'` at 392ea5d94545cafd1bb085c21eb66b0d4a6f4592

## Range
bad `392ea5d94545`, last good `766e6ea5b4d6`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2316769/test_classref26  [code=113253B  data=4224B  bss=42516B  procs=253]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
