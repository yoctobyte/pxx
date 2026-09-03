---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh cmath_nan_payload "$(/tmp/cmath_nan_payload)" "$(printf 'empty 7FF8000000000000\n1 7FF8000000000001`. The job's own `src` (`test/cmath_nan_payload.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/cmath_nan_payload.c at 2749b12c2e93 in step 2/2, `tools/expect_same.sh cmath_nan_payload "$(/tmp/cmath_nan_payload)" "$(printf 'empty 7FF8000000000000\n1 7FF800000000000…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/cmath_nan_payload.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh cmath_nan_payload "$(/tmp/cmath_nan_payload)" "$(printf 'empty 7FF8000000000000\n1 7FF8000000000001\n12345 7FF8000000003039\n0x10 7FF8000000000010\nabc 7FF8000000000000\n077 7FF800000000003F\nbig 7FF8000000000001')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/cmath_nan_payload.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2058534/cmath_nan_payload  [code=405272B  data=13264B  bss=73344B  procs=936]
Segmentation fault (core dumped)
expect_same: MISMATCH [cmath_nan_payload]
--- expected
+++ actual
@@ -1,7 +1 @@
-empty      7FF8000000000000
-1          7FF8000000000001
-12345      7FF8000000003039
-0x10       7FF8000000000010
-abc        7FF8000000000000
-077        7FF800000000003F
-big        7FF8000000000001
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-03 — auto-closed by the seven watcher: `lib-test#src:test/cmath_nan_payload.c` passes at 9edd70d02101 (tier full); it was red at 2749b12c2e93. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
