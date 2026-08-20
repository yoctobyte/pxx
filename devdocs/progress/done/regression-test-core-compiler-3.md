---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:compiler/compiler.pas@2 red at 003d733936aa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:35:45Z
- **Test source:** compiler/compiler.pas tools/progress.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:compiler/compiler.pas@2'` at 003d733936aa9bc279a77baeab9fda4b3c63000b

## Range
bad `003d733936aa`, last good `ad995742f8db`, 10 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3974770/pascal26-threadsafe-self /tmp/testmgr-scratch-3974770/pascal26-threadsafe-next differ: byte 97, line 1
(tail)
ok: /tmp/testmgr-scratch-3974770/pascal26-threadsafe-self.3975840.tmp  [code=8638147B  data=227176B  bss=211128564B  procs=2930]
ok: /tmp/testmgr-scratch-3974770/pascal26-threadsafe-next.3975840.tmp  [code=8638147B  data=227040B  bss=211128564B  procs=2930]
/tmp/testmgr-scratch-3974770/pascal26-threadsafe-self /tmp/testmgr-scratch-3974770/pascal26-threadsafe-next differ: byte 97, line 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-20 — auto-closed by the plexus watcher: `test-core#src:compiler/compiler.pas@2` passes at 003d733936aa (tier full); it was red at 003d733936aa. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
