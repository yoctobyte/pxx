---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_print_arg_eval_order.npy@1 red at 9df2717684a3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T05:03:29Z
- **Test source:** test/test_nilpy_print_arg_eval_order.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_print_arg_eval_order.npy@1'` at 9df2717684a330d02747d73cffe34ffb575ca9ac

## Range
bad `9df2717684a3`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-288097/test_nilpy_printorder26  [code=1325814B  data=32916B  bss=9564B  procs=1147]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
