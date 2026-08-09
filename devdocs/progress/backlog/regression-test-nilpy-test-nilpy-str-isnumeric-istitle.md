---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_str_isnumeric_istitle.npy red at 0d6de0cbeae1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T08:30:13Z
- **Test source:** test/test_nilpy_str_isnumeric_istitle.npy test/test_nilpy_str_isnumeric_istitle.expected +1

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_str_isnumeric_istitle.npy'` at 0d6de0cbeae14acc49cf9a7c6f3d007b61118319

## Range
bad `0d6de0cbeae1`, last good `4939f47ab883`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-749282/test_nilpy_isnumtitle26  [code=1576831B  data=35740B  bss=8948B  procs=1301]
ok: /tmp/testmgr-scratch-749282/test_nilpy_relimp26  [code=1576173B  data=35960B  bss=8596B  procs=1306]
diff: test/test_nilpy_relative_import.expected: No such file or directory

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
