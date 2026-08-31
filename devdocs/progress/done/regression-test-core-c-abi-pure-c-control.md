---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh c_abi_pure_c_control26 "$(/tmp/c_abi_pure_c_control26)" "$(printf 'dbl_first 10.00\nint_first 10.00`. The job's own `src` (`test/c_abi_pure_c_control.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_abi_pure_c_control.c at 0fd9454b879d in step 2/2, `tools/expect_same.sh c_abi_pure_c_control26 "$(/tmp/c_ab` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T17:18:35Z
- **Test source:** test/c_abi_pure_c_control.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh c_abi_pure_c_control26 "$(/tmp/c_abi_pure_c_control26)" "$(printf 'dbl_first 10.00\nint_first 10.00\nthree_ints 123\ntwo_dbl 17.50\nflt 10.00')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_abi_pure_c_control.c'` at 0fd9454b879d05263ffb548bb99fe9d5cef26c73

## Range
> **The named sha `0fd9454b879d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0fd9454b879d`, last good `9d59cd77e88e`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3157252/c_abi_pure_c_control26  [code=237336B  data=10552B  bss=63600B  procs=679]
expect_same: MISMATCH [c_abi_pure_c_control26]
--- expected
+++ actual
@@ -3,3 +3,6 @@
 three_ints 123
 two_dbl 17.50
 flt 10.00
+mix4 1234.00
+eight 204
+pairsum 17.50

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — auto-closed by the seven watcher: `test-core#src:test/c_abi_pure_c_control.c` passes at 1c963c732e1b (tier native); it was red at 0fd9454b879d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
