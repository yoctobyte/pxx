---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:compiler/compiler.pas@2 red at 21117f415284 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:08:00Z
- **Test source:** compiler/compiler.pas tools/progress.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:compiler/compiler.pas@2'` at 21117f4152845a44e578a5eb04dc3af250a0b935

## Range
bad `21117f415284`, last good `8eb2ce583499`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3918410/pascal26-threadsafe-self /tmp/testmgr-scratch-3918410/pascal26-threadsafe-next differ: byte 97, line 1
(tail)
ok: /tmp/testmgr-scratch-3918410/pascal26-threadsafe-self.3919925.tmp  [code=8638147B  data=227176B  bss=211128564B  procs=2930]
ok: /tmp/testmgr-scratch-3918410/pascal26-threadsafe-next.3919925.tmp  [code=8638147B  data=227040B  bss=211128564B  procs=2930]
/tmp/testmgr-scratch-3918410/pascal26-threadsafe-self /tmp/testmgr-scratch-3918410/pascal26-threadsafe-next differ: byte 97, line 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
