---
prio: 70
---

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-opt#src:test/c_inline_strlit_arg.c red at 36d1bffda39d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T15:30:51Z
- **Test source:** test/c_inline_strlit_arg.c

## Repro
`tools/testmgr.py --tier opt --job 'test-opt#src:test/c_inline_strlit_arg.c'` at 36d1bffda39d58099b403745c48b95cd8c1d7c58

## Range
bad `36d1bffda39d`, last good `dbed942785d0`, 52 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF O1: test_math_unit

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
