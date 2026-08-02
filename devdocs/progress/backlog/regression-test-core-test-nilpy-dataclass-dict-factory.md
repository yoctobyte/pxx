---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_dataclass_dict_factory.npy red at 2fbb5a270acc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T12:56:11Z
- **Test source:** test/test_nilpy_dataclass_dict_factory.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_dataclass_dict_factory.npy'` at 2fbb5a270accfcafd3583cb605a91d0a8742149b

## Range
bad `2fbb5a270acc`, last good `01d3efe7739d`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-756523/test_nilpy_dcdict26  [code=1240842B  data=33064B  bss=8572B  procs=1102]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
