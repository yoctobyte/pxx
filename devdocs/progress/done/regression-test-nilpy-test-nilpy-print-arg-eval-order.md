---
prio: 70
status: done
owner: claude-AN
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

## Fixed 2026-08-04 (claude-AN — I caused it)

Not a code regression: `c8093ef11` **overwrote an existing test file**.
`test/test_nilpy_print_arg_eval_order.npy` already existed — it is the test for
[[bug-nilpy-print-emits-arguments-before-evaluating-later-ones]], wired at
Makefile line 1110 with its own expectation ("label = ERR", the star-unpack
rows, …). I wrote a new test for a *different* print bug under the same name and
added a *second* Makefile recipe for it, so the file passed my recipe and failed
the original's.

The compiler change in `c8093ef11` is correct and unaffected; only the test file
was clobbered.

Restored the original from `c8093ef11^` and renamed mine to
`test_nilpy_print_container_arg_freshness.npy` (+ `.expected`), which is what it
actually tests: that a container argument's TEXT is produced after every
argument is evaluated. Both recipes now run their own file, and both pass.

**The check that would have caught it:** the two names were close enough to read
as the same concern — "print arg eval order" vs "print evaluates args before
writing" — so `ls test/ | grep <topic>` before creating a test file is worth
more than it looks. A new test that needs a NEW Makefile recipe beside an
existing one for the same file is the tell.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
