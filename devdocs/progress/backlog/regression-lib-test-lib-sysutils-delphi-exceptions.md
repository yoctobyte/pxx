---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 3 is `tools/expect_same.sh lib_sysutils_delphi_exc.1 "$(/tmp/lib_sysutils_delphi_exc | grep -c '=ok')" "21"`. The job's own `src` (`test/lib_sysutils_delphi_exceptions.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 17 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_sysutils_delphi_exceptions.pas at c543b335fb2f in step 2/3, `tools/expect_same.sh lib_sysutils_delphi_exc.1 "$(/tmp/lib_sysutils_delphi_exc | grep -c '=ok')" "21"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T19:55:28Z
- **Test source:** test/lib_sysutils_delphi_exceptions.pas tools/expect_same.sh
- **Failing step:** line 2 of 3 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh lib_sysutils_delphi_exc.1 "$(/tmp/lib_sysutils_delphi_exc | grep -c '=ok')" "21"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_sysutils_delphi_exceptions.pas'` at c543b335fb2fd97de3457a88e4f637011db157e5

## Range
> **The named sha `c543b335fb2f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c543b335fb2f`, last good `6d04b14cd88d`, **20 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
ok: /tmp/testmgr-scratch-3110689/lib_sysutils_delphi_exc  [code=335640B  data=33112B  bss=87780B  procs=843]
expect_same: MISMATCH [lib_sysutils_delphi_exc.1]
--- expected
+++ actual
@@ -1 +1 @@
-21
+25

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
