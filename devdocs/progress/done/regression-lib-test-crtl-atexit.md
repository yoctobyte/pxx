---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 8 of 10 is `tools/expect_same.sh crtl_atexit.3 "$(/tmp/crtl_atexit n)" "registered ok=100 bad=0"`. The job's own `src` (`test/crtl_atexit.c`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_atexit.c at 2749b12c2e93 in step 8/10, `tools/expect_same.sh crtl_atexit.3 "$(/tmp/crtl_atexit n)" "registered ok=100 bad=0"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T17:59:39Z
- **Test source:** test/crtl_atexit.c tools/expect_same.sh +1
- **Failing step:** line 8 of 10 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh crtl_atexit.3 "$(/tmp/crtl_atexit n)" "registered ok=100 bad=0"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_atexit.c'` at 2749b12c2e93b397f6e384a6c05176831c9378fa

## Range
> **The named sha `2749b12c2e93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2749b12c2e93`, last good `08b0f50df2ac`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
ok: /tmp/testmgr-scratch-2058534/crtl_atexit  [code=319256B  data=13256B  bss=72856B  procs=835]
main-returns
h3
h2
h1
via-exit
child-exit
via-_Exit
expect_same: MISMATCH [crtl_atexit.3]
--- expected
+++ actual
@@ -1 +1 @@
-registered ok=100 bad=0
+registered ok=17683 bad=0

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-03 — auto-closed by the seven watcher: `lib-test#src:test/crtl_atexit.c` passes at 9edd70d02101 (tier full); it was red at 2749b12c2e93. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
