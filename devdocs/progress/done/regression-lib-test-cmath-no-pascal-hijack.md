---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh cmath_no_pascal_hijack "$(/tmp/cmath_no_pascal_hijack)" "$(printf 'pow=1024 1.41421\nlog=1.38629436`. The job's own `src` (`test/cmath_no_pascal_hijack.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/cmath_no_pascal_hijack.c at 2749b12c2e93 in step 2/2, `tools/expect_same.sh cmath_no_pascal_hijack "$(/tmp/cmath_no_pascal_hijack)" "$(printf 'pow=1024 1.41421\nlog=1.3862943…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/cmath_no_pascal_hijack.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh cmath_no_pascal_hijack "$(/tmp/cmath_no_pascal_hijack)" "$(printf 'pow=1024 1.41421\nlog=1.386294361 log10=3.000000000 log2=3.000000000\nexp=2.718281828\natan2=0.785398163 0.463647609 1.107148718\ncopysign=-3 3\nisnan=1 0\nisinf=1 0\nnan=1 1\nhypot=5.000000000 fmod=1\nsqrt=1.414
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/cmath_no_pascal_hijack.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
ok: /tmp/testmgr-scratch-2058534/cmath_no_pascal_hijack  [code=405272B  data=13448B  bss=73344B  procs=935]
expect_same: MISMATCH [cmath_no_pascal_hijack]
--- expected
+++ actual
@@ -1,10 +1,10 @@
-pow=1024 1.41421
-log=1.386294361 log10=3.000000000 log2=3.000000000
-exp=2.718281828
-atan2=0.785398163 0.463647609 1.107148718
-copysign=-3 3
-isnan=1 0
-isinf=1 0
-nan=1 1
-hypot=5.000000000 fmod=1
-sqrt=1.414213562 ceil=-2 floor=-3
+pow=2.27899e-317 -0
+log=0.000000000 log10=0.000000000 log2=0.000000000
+exp=0.000000000
+atan2=0.000000000 0.000000000 0.000000000
+copysign=2.27909e-317 2.07508e-322
+isnan=18019 0
+isinf=18019 0
+nan=18020 0
+hypot=0.000000000 fmod=5.92879e-323
+sqrt=0.000000000 ceil=-0 floor=0

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-03 — auto-closed by the seven watcher: `lib-test#src:test/cmath_no_pascal_hijack.c` passes at 9edd70d02101 (tier full); it was red at 2749b12c2e93. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
