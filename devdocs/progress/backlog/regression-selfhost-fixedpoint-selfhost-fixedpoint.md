---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh red at 21117f415284 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:08:00Z
- **Test source:** tools/selfhost_fixedpoint.sh

## Repro
`tools/testmgr.py --tier native --job 'selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh'` at 21117f4152845a44e578a5eb04dc3af250a0b935

## Range
bad `21117f415284`, last good `8eb2ce583499`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3918410/selfhost-fp-3919810/stage_2a /tmp/testmgr-scratch-3918410/selfhost-fp-3919810/tested differ: byte 97, line 1
(tail)
converged after 2 round(s) from pinned: the compiler reproduces itself
FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26
      (both may self-reproduce — that is exactly the point: two distinct
       fixedpoints means the binary we test with is not the one these
       sources define. Local seed contamination, or a self-perpetuating
       miscompile.)
/tmp/testmgr-scratch-3918410/selfhost-fp-3919810/stage_2a /tmp/testmgr-scratch-3918410/selfhost-fp-3919810/tested differ: byte 97, line 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
