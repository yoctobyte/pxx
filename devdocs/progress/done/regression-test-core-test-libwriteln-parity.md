---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_libwln26 "$(/tmp/test_libwln26)" "$(cat test/test_libwriteln_parity.expected)"`. The job's own `src` (`test/test_libwriteln_parity.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_libwriteln_parity.pas at fa5e9ef55813 in step 2/2, `tools/expect_same.sh test_libwln26 "$(/tmp/test_libwln26)" "$(cat test/test_libwriteln_parity.expected)"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T08:23:51Z
- **Test source:** test/test_libwriteln_parity.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_libwriteln_parity.expected`.
  ```
  tools/expect_same.sh test_libwln26 "$(/tmp/test_libwln26)" "$(cat test/test_libwriteln_parity.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_libwriteln_parity.pas'` at fa5e9ef558138c5e9014e641af2fe4591b232cf9

## Range
> **The named sha `fa5e9ef55813` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fa5e9ef55813`, last good `47b8c3285253`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1079712/test_libwln26  [code=331544B  data=32708B  bss=85500B  procs=845]
expect_same: MISMATCH [test_libwln26]
--- expected
+++ actual
@@ -3,7 +3,7 @@
 int64    builtin=9223372036854775807
 int64    library=9223372036854775807
 qword    builtin=9000000000
-qword    library=9000000000
+qword    library=
 bool     builtin=TRUE
 bool     library=TRUE
 boolF    builtin=FALSE

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `test-core#src:test/test_libwriteln_parity.pas` passes at a4ce5c00774a (tier native); it was red at fa5e9ef55813. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
