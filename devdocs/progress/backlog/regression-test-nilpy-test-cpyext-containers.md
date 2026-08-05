---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_containers.npy red at 34c41bde6fd6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T19:36:23Z
- **Test source:** test/test_cpyext_containers.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_containers.npy'` at 34c41bde6fd66529206b2891337066a5a9fae50c

## Range
bad `34c41bde6fd6`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:16: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
(tail)
pascal26:16: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
  near:  interface uses pxxcio  ../../lib/cpyext/src/pyruntime.c >>>  ./container_ext_module.c  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
