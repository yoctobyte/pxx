---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh cmath_lround "$(/tmp/cmath_lround)" "$(printf '0.5 lround=1 llround=1 lrint=0\n1.5 lround=2 llround`. The job's own `src` (`test/cmath_lround.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/cmath_lround.c at 2749b12c2e93 in step 2/2, `tools/expect_same.sh cmath_lround "$(/tmp/cmath_lround)" "$(printf '0.5 lround=1 llround=1 lrint=0\n1.5 lround=2 llroun…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/cmath_lround.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh cmath_lround "$(/tmp/cmath_lround)" "$(printf '0.5 lround=1 llround=1 lrint=0\n1.5 lround=2 llround=2 lrint=2\n2.5 lround=3 llround=3 lrint=2\n3.5 lround=4 llround=4 lrint=4\n-0.5 lround=-1 llround=-1 lrint=0\n-1.5 lround=-2 llround=-2 lrint=-2\n-2.5 lround=-3 llround=-3 lrint=-
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/cmath_lround.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
ok: /tmp/testmgr-scratch-2058534/cmath_lround  [code=405272B  data=12952B  bss=73344B  procs=935]
expect_same: MISMATCH [cmath_lround]
--- expected
+++ actual
@@ -1,10 +1,10 @@
-0.5 lround=1 llround=1 lrint=0
-1.5 lround=2 llround=2 lrint=2
-2.5 lround=3 llround=3 lrint=2
-3.5 lround=4 llround=4 lrint=4
--0.5 lround=-1 llround=-1 lrint=0
--1.5 lround=-2 llround=-2 lrint=-2
--2.5 lround=-3 llround=-3 lrint=-2
-2.7 lround=3 llround=3 lrint=3
--2.7 lround=-3 llround=-3 lrint=-3
-0.0 lround=0 llround=0 lrint=0
+0.0 lround=72057594037945954 llround=72057594037927936 lrint=0
+0.0 lround=144115188075873890 llround=144115188075855872 lrint=144115188075855872
+0.0 lround=216172782113801826 llround=216172782113783808 lrint=144115188075855872
+0.0 lround=288230376151729762 llround=288230376151711744 lrint=288230376151711744
+0.0 lround=-72057594037909918 llround=-1 lrint=72057594037927935
+0.0 lround=-144115188075837854 llround=-72057594037927937 lrint=-72057594037927937
+0.0 lround=-216172782113765790 llround=-144115188075855873 lrint=-72057594037927937
+0.0 lround=216172782113801826 llround=216172782113783808 lrint=216172782113783808
+0.0 lround=-216172782113765790 llround=-144115188075855873 lrint=-144115188075855873
+0.0 lround=18018 llround=0 lrint=0

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
