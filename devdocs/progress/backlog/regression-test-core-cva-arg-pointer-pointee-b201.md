---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `/tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.sh cva_arg_pointer_pointee_b20126-rc "$?" "42"`. The job's own `src` (`test/cva_arg_pointer_pointee_b201.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cva_arg_pointer_pointee_b201.c at 6e622be95680 in step 2/2, `/tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.s` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T08:27:47Z
- **Test source:** test/cva_arg_pointer_pointee_b201.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  /tmp/cva_arg_pointer_pointee_b20126; tools/expect_same.sh cva_arg_pointer_pointee_b20126-rc "$?" "42"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/cva_arg_pointer_pointee_b201.c'` at 6e622be956803d7e310994163d5f9e55db4eddc9

## Range
bad `6e622be95680`, last good `a96ef413f872`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1597241/cva_arg_pointer_pointee_b20126  [code=237336B  data=10408B  bss=63600B  procs=675]
expect_same: MISMATCH [cva_arg_pointer_pointee_b20126-rc]
--- expected
+++ actual
@@ -1 +1 @@
-42
+3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
