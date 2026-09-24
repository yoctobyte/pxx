---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 4 of 4 is `grep -q "var parameter x of TC.M is Int64 (8 bytes) and needs a variable of exactly that type" /tmp/test_varwidth_refuse`. The job's own `src` (`test/test_var_param_width_rule_accepts_exact_and_cast.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_var_param_width_rule_accepts_exact_and_cast.pas at e575f1ec8cd0 in step 4/4, `grep -q "var parameter x of TC.M is Int64 (8 bytes) and needs a variable of exactly that type" /tmp/test_varwidth_refus…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T21:57:56Z
- **Test source:** test/test_var_param_width_rule_accepts_exact_and_cast.pas tools/expect_same.sh +1
- **Failing step:** line 4 of 4 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  grep -q "var parameter x of TC.M is Int64 (8 bytes) and needs a variable of exactly that type" /tmp/test_varwidth_refused.log
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_var_param_width_rule_accepts_exact_and_cast.pas'` at e575f1ec8cd01608a0aed72bda9f48d75e9f6582

## Range
> **The named sha `e575f1ec8cd0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e575f1ec8cd0`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-2195644/test_varwidth_ok26  [code=20589B  data=4552B  bss=35388B  procs=158  codeseg=24288B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-24 — auto-closed by the borg watcher: `test-core#src:test/test_var_param_width_rule_accepts_exact_and_cast.pas` passes at 635caa48b11c (tier native); it was red at e575f1ec8cd0. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
