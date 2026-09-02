---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_typeinfo_typedata26 "$(/tmp/test_typeinfo_typedata26)" "$(printf 'ShortInt kind=1 name=ShortIn`. The job's own `src` (`test/test_typeinfo_typedata.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_typeinfo_typedata.pas at 5be4c0665c1e in step 2/2, `tools/expect_same.sh test_typeinfo_typedata26 "$(/tmp/test_typeinfo_typedata26)" "$(printf 'ShortInt kind=1 name=ShortI…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T12:20:52Z
- **Test source:** test/test_typeinfo_typedata.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_typeinfo_typedata26 "$(/tmp/test_typeinfo_typedata26)" "$(printf 'ShortInt kind=1 name=ShortInt ord=0 min=-128 max=127\nByte kind=1 name=Byte ord=1 min=0 max=255\nSmallInt kind=1 name=SmallInt ord=2 min=-32768 max=32767\nWord kind=1 name=Word ord=3 min=0 max=65535\nInteger
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_typeinfo_typedata.pas'` at 5be4c0665c1e7f765cbe019fb9f87b725fb1f5d0

## Range
> **The named sha `5be4c0665c1e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5be4c0665c1e`, last good `adb676557642`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1141262/test_typeinfo_typedata26  [code=134936B  data=11328B  bss=43716B  procs=323]
expect_same: MISMATCH [test_typeinfo_typedata26]
--- expected
+++ actual
@@ -9,8 +9,8 @@
 Char kind=2 name=Char ord=1 min=0 max=255
 Single kind=4 name=Single float=0
 Double kind=4 name=Double float=1
-TSub kind=1 name=TSub ord=4 min=1 max=10
-TSubB kind=1 name=TSubB ord=4 min=-5 max=5
+TSub kind=1 name=TSub ord=1 min=1 max=10
+TSubB kind=1 name=TSubB ord=0 min=-5 max=5
 TMyInt kind=1 name=Integer ord=4 min=-2147483648 max=2147483647
 TStr20 kind=7 name=TStr20 ord=0 min=0 max=20
 TS kind=5 name=TS ord=5 elemkind=3 elemsize=4 min=0 max=2 comp=TEn compcount=3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — auto-closed by the seven watcher: `test-core#src:test/test_typeinfo_typedata.pas` passes at c58f2c1bc326 (tier native); it was red at 5be4c0665c1e. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
