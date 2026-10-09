---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 7 is `tools/assert_no_leak.sh nilpy_lambda_captured 300 /tmp/test_nilpy_lamcaph26 leak 5000`. The job's own `src` (`test/test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it.npy`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `assert_no_leak`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it.npy@2 at 59caf859488c in step 2/7, `tools/assert_no_leak.sh nilpy_lambda_captured 300 /tmp/test_nilpy_lamcaph26 leak 5000` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-09T16:08:40Z
- **Test source:** test/test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it.npy tools/assert_no_leak.sh +1
- **Failing step:** line 2 of 7 of the job's recipe; it names `tools/assert_no_leak.sh`.
  ```
  tools/assert_no_leak.sh nilpy_lambda_captured 300 /tmp/test_nilpy_lamcaph26 leak 5000
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it.npy@2'` at 59caf859488c8fd3be06b0103dec455d55593f6b

## Range
bad `59caf859488c`, last good `f159f2ee43df`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-831629/test_nilpy_lamcaph26  [code=666726B  data=111153B  bss=68972B  procs=2391  codeseg=667360B]
assert_no_leak[nilpy_lambda_captured]: only 56 allocations — too few to show anything.
  pxx-census: allocs=56 frees=23 live=33 bytes=3744 reuse=21 list=0 bump=35 arenas=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
