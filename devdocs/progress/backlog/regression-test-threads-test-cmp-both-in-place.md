---
prio: 70
track: A+O
---

> **RETRACKED P → A+O by the coordinator, 2026-08-30.** The guess was P; the argument for
> A+O is bounded and is set out under "Retrack" below. It is also **not a regression** — see
> there.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_cmp_both_in_place.pas@2 red at 0aa01425dbdc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:36:29Z
- **Test source:** test/test_cmp_both_in_place.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_cmp_both_in_place.pas@2'` at 0aa01425dbdc0fe8f676f40a314848ddefd78426

## Range
> **The named sha `0aa01425dbdc` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aa01425dbdc`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-3881983/test_cbip026  [code=83375B  data=2008B  bss=42460B  procs=131]
expect_same: MISMATCH [aarch64/test_cbip_a64_0]
--- expected
+++ actual
@@ -1 +1 @@
-3896084(printf 'acc=49149\none=16383\ndone')
+3896084(tools/run_target.sh aarch64 /tmp/testmgr-scratch-3881983/test_cbip_a64_0)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Retrack P → A+O, and it is not a regression — 2026-08-30, coordinator

**Four bounded facts, no story.**

1. **The failing job is `aarch64/test_cbip_a64_0`.** The mismatch is on the aarch64 arm, not
   on anything thread- or Pascal-frontend-shaped. `test-threads` is the tier it ran in, not
   the subject.
2. **The test is `frank-optimize-b4`'s.** `test_cmp_both_in_place.pas` (`test_cbip`) matches
   `d1535b899` — *"-O3 aarch64 reads BOTH compare operands in place — W1 slices 5+7"* —
   landed within the hour. This is that commit's own regression test.
3. **It is the job's FIRST-EVER RUN.** The stub says so: no earlier passing sha, no interval
   contains a cause, no idle bisect will happen. **A first-run red is a finding about the
   job, not a regression from the commits around it** — and filing it as `regression-` is
   what made it look like one.
4. **The diff compares two COMMAND STRINGS, not two outputs:**

   ```
   -3896084(printf 'acc=49149\none=16383\ndone')
   +3896084(tools/run_target.sh aarch64 /tmp/testmgr-scratch-.../test_cbip_a64_0)
   ```

   Expected holds `printf '...'`; actual holds `tools/run_target.sh aarch64 …`. Neither side
   is program output. **The expectation captured the command instead of running it**, so the
   comparison could never have passed and its greenness on other arms says nothing either.

So: the compiler is not implicated by this row, the aarch64 arm is not shown to be wrong,
and **nothing here is evidence for or against `d1535b899`.** The row is an authoring defect
in the expectation, in the lane that owns the test.

Also note the `/tmp/testmgr-scratch-3881983/` path on the actual side: an expected output
must never contain an absolute `/tmp` path, because testmgr rewrites it
(`devdocs/dev/gating-and-waiting.md`). That is a second reason this pair can never match.

**This is exactly the shape face 132b names** — `run_target.sh` standing where a program's
output belongs. Third instance of the harness-artefact-read-as-a-result family.
