---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh cmath_integral_family "$(/tmp/cmath_integral_family)" "$(printf 'fabs(-0)=+0\ntrunc(-0.5)=-0\nround`. The job's own `src` (`test/cmath_integral_family.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/cmath_integral_family.c at 2749b12c2e93 in step 2/2, `tools/expect_same.sh cmath_integral_family "$(/tmp/cmath_integral_family)" "$(printf 'fabs(-0)=+0\ntrunc(-0.5)=-0\nroun…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/cmath_integral_family.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh cmath_integral_family "$(/tmp/cmath_integral_family)" "$(printf 'fabs(-0)=+0\ntrunc(-0.5)=-0\nround(-0)=-0\nrint(-0.5)=-0\nfrexp(-0)=-0 e=0\nmodf(-1) fr=-0 ip=-1\ntrunc(1e300)=+1e+300\nround(-1e300)=-1e+300\nmodf(1e300) fr=+0 ip=+1e+300\nround(0.49999999999999994)=+0\nfrexp(inf)
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/cmath_integral_family.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2058534/cmath_integral_family  [code=405272B  data=13512B  bss=73344B  procs=936]
Segmentation fault (core dumped)
expect_same: MISMATCH [cmath_integral_family]
--- expected
+++ actual
@@ -1,11 +1 @@
-fabs(-0)=+0
-trunc(-0.5)=-0
-round(-0)=-0
-rint(-0.5)=-0
-frexp(-0)=-0 e=0
-modf(-1) fr=-0 ip=-1
-trunc(1e300)=+1e+300
-round(-1e300)=-1e+300
-modf(1e300) fr=+0 ip=+1e+300
-round(0.49999999999999994)=+0
-frexp(inf)=+inf
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
