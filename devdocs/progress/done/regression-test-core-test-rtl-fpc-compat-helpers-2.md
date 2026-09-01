---
prio: 70
track: A
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_rtl_fpc_compat_helpers26 "$(/tmp/test_rtl_fpc_compat_helpers26 | tail -1)" "total ok 23 / 23"`. The job's own `src` (`test/test_rtl_fpc_compat_helpers.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rtl_fpc_compat_helpers.pas at 970eabd8eadf in step 2/2, `tools/expect_same.sh test_rtl_fpc_compat_helpers26 "$(/tmp/test_rtl_fpc_compat_helpers26 | tail -1)" "total ok 23 / 23"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T19:41:04Z
- **Test source:** test/test_rtl_fpc_compat_helpers.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_rtl_fpc_compat_helpers26 "$(/tmp/test_rtl_fpc_compat_helpers26 | tail -1)" "total ok 23 / 23"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rtl_fpc_compat_helpers.pas'` at 970eabd8eadfc9c22bb57cdf2546668c082ea498

## Range
> **The named sha `970eabd8eadf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `970eabd8eadf`, last good `1e37a55f6748`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2132418/test_rtl_fpc_compat_helpers26  [code=442136B  data=53188B  bss=86044B  procs=1109]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_rtl_fpc_compat_helpers26]
--- expected
+++ actual
@@ -1 +1 @@
-total ok 23 / 23
+ok memrange-unsigned

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Verified fixed at HEAD — 2026-09-01, frankZ

Duplicate; fixed by `d5e0a1e48` (frankB), the managed-ownership seam. Re-derived
at `c9602d5ce`, binary `76c8be9064e0`, `converged after 2 round(s)`:

```
./compiler/pascal26 -Fulib/rtl test/test_rtl_fpc_compat_helpers.pas /tmp/r && /tmp/r
rc=0   ok varcmp-i64   total ok 23 / 23
```

`-Fulib/rtl` is load-bearing and belongs in any future repro of this one:
without it the same source exits 0 and the SIGSEGV does not happen. The recipe
passes it; a repro that drops it reports a false green.
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6b3b54ce4.
