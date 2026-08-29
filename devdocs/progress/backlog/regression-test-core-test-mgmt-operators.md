---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_mgmt_operators.pas red at 47277dd0e52b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T20:18:59Z
- **Test source:** test/test_mgmt_operators.pas test/test_mgmt_operators.expected +5

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_mgmt_operators.pas'` at 47277dd0e52b8594fdad3fb15eb2be2d2a518f41

## Range
> **The named sha `47277dd0e52b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `47277dd0e52b`, last good `0c8459022373`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1238665/test_mgmt_operators26  [code=297424B  data=24744B  bss=75692B  procs=730]
FAIL: an array of a managed record compiled

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
