---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_c_abi_intra26 "$(/tmp/test_c_abi_intra26)" "$(printf 'dbl_first 1000\nint_first 1000\nthree_in`. The job's own `src` (`test/test_c_abi_intra_c_calls.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_abi_intra_c_calls.pas at 0fd9454b879d in step 2/2, `tools/expect_same.sh test_c_abi_intra26 "$(/tmp/test_c_a` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T17:18:35Z
- **Test source:** test/test_c_abi_intra_c_calls.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_c_abi_intra26 "$(/tmp/test_c_abi_intra26)" "$(printf 'dbl_first 1000\nint_first 1000\nthree_ints 123\ntwo_dbl 1750\nflt 1000\ndbl_arg_int_ret 1000')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_abi_intra_c_calls.pas'` at 0fd9454b879d05263ffb548bb99fe9d5cef26c73

## Range
> **The named sha `0fd9454b879d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0fd9454b879d`, last good `9d59cd77e88e`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3157252/test_c_abi_intra26  [code=151320B  data=5712B  bss=42500B  procs=539]
expect_same: MISMATCH [test_c_abi_intra26]
--- expected
+++ actual
@@ -4,3 +4,6 @@
 two_dbl 1750
 flt 1000
 dbl_arg_int_ret 1000
+mix4 123400
+eight 204
+pairsum 1750

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — auto-closed by the seven watcher: `test-core#src:test/test_c_abi_intra_c_calls.pas` passes at 1c963c732e1b (tier native); it was red at 0fd9454b879d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
