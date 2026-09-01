---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_threadsafe_refcount_lockfree26 "$(/tmp/test_threadsafe_refcount_lockfree26 | tail -n 2)" "$(pr`. The job's own `src` (`test/test_threadsafe_refcount_lockfree.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_refcount_lockfree.pas at 1e37a55f6748 in step 2/2, `tools/expect_same.sh test_threadsafe_refcount_lockfree26 "$(/tmp/test_threadsafe_refcount_lockfree26 | tail -n 2)" "$(p…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T19:24:15Z
- **Test source:** test/test_threadsafe_refcount_lockfree.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_threadsafe_refcount_lockfree26 "$(/tmp/test_threadsafe_refcount_lockfree26 | tail -n 2)" "$(printf 'fail=0\nTSRCLOCKFREE OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_threadsafe_refcount_lockfree.pas'` at 1e37a55f674860a0f2d42e5500453272b3cf9451

## Range
> **The named sha `1e37a55f6748` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1e37a55f6748`, last good `645259ff18c0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2008261/test_threadsafe_refcount_lockfree26  [code=130840B  data=6712B  bss=43756B  procs=286]
expect_same: MISMATCH [test_threadsafe_refcount_lockfree26]
--- expected
+++ actual
@@ -1,2 +1,2 @@
-fail=0
-TSRCLOCKFREE OK
+fail=3
+TSRCLOCKFREE FAILED

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-threads#src:test/test_threadsafe_refcount_lockfree.pas` passes at 889bfcf73256 (tier native); it was red at 1e37a55f6748. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
