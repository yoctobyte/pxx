---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 3 is `tools/expect_same.sh crtl_poll_set "$(/tmp/crtl_poll_set)" "$(printf 'timeout r=0 rev0=0 rev1=0\nready r=1 rev0=0 rev1in`. The job's own `src` (`test/crtl_poll_set.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_poll_set.c at 2749b12c2e93 in step 2/3, `tools/expect_same.sh crtl_poll_set "$(/tmp/crtl_poll_set)" "$(printf 'timeout r=0 rev0=0 rev1=0\nready r=1 rev0=0 rev1i…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/crtl_poll_set.c tools/expect_same.sh
- **Failing step:** line 2 of 3 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh crtl_poll_set "$(/tmp/crtl_poll_set)" "$(printf 'timeout r=0 rev0=0 rev1=0\nready r=1 rev0=0 rev1in=1\nboth r=2 in0=1 in1=1\nnval r=1 nval=1\nzero r=0')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_poll_set.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
ok: /tmp/testmgr-scratch-2058534/crtl_poll_set  [code=311064B  data=13256B  bss=72860B  procs=831]
expect_same: MISMATCH [crtl_poll_set]
--- expected
+++ actual
@@ -1,5 +1,5 @@
-timeout r=0 rev0=0 rev1=0
-ready r=1 rev0=0 rev1in=1
-both r=2 in0=1 in1=1
-nval r=1 nval=1
-zero r=0
+timeout r=17650 rev0=0 rev1=0
+ready r=17650 rev0=0 rev1in=0
+both r=17651 in0=0 in1=0
+nval r=17651 nval=0
+zero r=17651

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
