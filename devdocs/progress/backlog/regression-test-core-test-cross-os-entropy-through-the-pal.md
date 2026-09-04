---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh entpal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/entpal.wasm)" "ENTROPY OK"`. The job's own `src` (`test/test_cross_os_entropy_through_the_pal.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_cross_os_entropy_through_the_pal.pas@2 at e2eece6e6f94 in step 2/4, `tools/expect_same.sh entpal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/entpal.wasm)" "ENTROPY OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T13:44:32Z
- **Test source:** test/test_cross_os_entropy_through_the_pal.pas tools/expect_same.sh +2
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh tools/run_target.sh`.
  ```
  tools/expect_same.sh entpal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/entpal.wasm)" "ENTROPY OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cross_os_entropy_through_the_pal.pas@2'` at e2eece6e6f941c87b537fcf745b3880ee6678403

## Range
> **The named sha `e2eece6e6f94` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e2eece6e6f94`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-1151156/entpal.wasm  [code=15634B  data=6416B  bss=1092144B  procs=530]
wasmtime not found (looked on PATH and in ~/.local/bin)
expect_same: MISMATCH [entpal26/wasm32]
--- expected
+++ actual
@@ -1 +1 @@
-ENTROPY OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
