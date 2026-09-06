---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 5 of 5 is `overall=0; ran=0; want=0; \ for t in i386 aarch64 arm32 riscv32; do \ want=$((want+1)); \ case $t in i386) q=qemu-i386;;`. The job's own `src` (`test/c_cross_time_and_exit_through_the_pal.c`, 5 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_cross_time_and_exit_through_the_pal.c at a8179a73ea84 in step 5/5, `overall=0; ran=0; want=0; \ for t in i386 aarch64 arm32 riscv32; do \ want=$((want+1)); \ case $t in i386) q=qemu-i386;…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T19:21:53Z
- **Test source:** test/c_cross_time_and_exit_through_the_pal.c tools/expect_same.sh +3
- **Failing step:** line 5 of 5 of the job's recipe; it names `test/c_cross_time_and_exit_through_the_pal_noclock.expected test/c_cross_time_and_exit_through_the_pal.expected test/c_cross_time_and_exit_through_the_pal.c tools/run_target.sh`.
  ```
  overall=0; ran=0; want=0; \ for t in i386 aarch64 arm32 riscv32; do \ want=$((want+1)); \ case $t in i386) q=qemu-i386;; aarch64) q=qemu-aarch64;; arm32) q=qemu-arm;; riscv32) q=qemu-riscv32;; esac; \ if ! command -v $q >/dev/null 2>&1; then echo " c_pal_time: SKIP $t ($q absent, NOT verified)"; con
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_cross_time_and_exit_through_the_pal.c'` at a8179a73ea84fd9bc165805924d5273dcb0d2d89

## Range
> **The named sha `a8179a73ea84` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a8179a73ea84`, last good `8bef014c7f6c`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2636906/c_pal_time26  [code=356120B  data=15184B  bss=82036B  procs=888]
pal time+exit ok (clock expected: 1)
  c_pal_time: PASS i386 (exit 7 through exit(), clock expected 1)
  c_pal_time: PASS i386 (must-fail control rejected expectation 0)
  c_pal_time: PASS aarch64 (exit 7 through exit(), clock expected 1)
  c_pal_time: PASS aarch64 (must-fail control rejected expectation 0)
  c_pal_time: PASS arm32 (exit 7 through exit(), clock expected 1)
  c_pal_time: PASS arm32 (must-fail control rejected expectation 0)
  c_pal_time: FAIL riscv32 rc=1
      FAIL clock_gettime-rc: got 1 want 0
      FAIL time-plausible: got 1 want 0
      FAIL clock-advanced: got 1 want 0
      pal time+exit: 3 row(s) FAILED
  c_pal_time: CONTROL DID NOT FAIL on riscv32 (rc=7) -- the check cannot come out false, so the PASS above means nothing
  c_pal_time: 4 of 4 cross targets measured
  c_pal_time: RED

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
