---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 2 is `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$l`. The job's own `src` (`tools/compiler_srchash.sh`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-abi-mixed-link#src:tools/compiler_srchash.sh at 95fc8aff2016 in step 1/2, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T16:29:52Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +2
- **Failing step:** line 1 of 2 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$livesrc" ]; then \ echo "tools/compiler_srchash.sh produced NO source hash, so this check cannot run."; \ echo " An empty result means 'could not measure', never 'measured and they
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-c-abi-mixed-link#src:tools/compiler_srchash.sh'` at 95fc8aff20164f125a7b079cb02915ccc4855cd1

## Range
bad `95fc8aff2016`, last good `0fe9137ee7c0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: deadbeef
  tree sources:  fa41e93c533b3a32ef664eee29208684c57d1f7d581fc1ffd34f1e9ae1a3e83a
  THE FILE SET CHANGED, not just its contents: stamp 214 files, tree 215.
  A file was ADDED TO or REMOVED FROM the hashed set. The set is five
  globs -- compiler/compiler.pas, compiler/*.inc, compiler/builtin/*.pas,
  lib/rtl/*.pas, lib/asmcore/*.pas -- so an untracked stray dropped into
  any of them counts as a source.
  Nothing untracked or modified locally, so no stray file explains it:
  this stamp was written for a DIFFERENT TREE. Usual cause is a pull
  -- or a sync, which pulls -- with no rebuild after it.
A stamp NEWER than sources it does not describe is how this step
printed 'verified' three times in one day without building anything.
Recover with:  rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-08 — the seven watcher saw `test-c-abi-mixed-link#src:tools/compiler_srchash.sh` GREEN at b29428afe251 (tier full) and did NOT close this: this is a repeat stub (`regression-test-c-abi-mixed-link-compiler-srchash-2`, not `regression-test-c-abi-mixed-link-compiler-srchash`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-08 — the seven watcher saw `test-c-abi-mixed-link#src:tools/compiler_srchash.sh` GREEN at 7deb97fbdb2a (tier full) and did NOT close this: this is a repeat stub (`regression-test-c-abi-mixed-link-compiler-srchash-2`, not `regression-test-c-abi-mixed-link-compiler-srchash`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-11 — the seven watcher saw `test-c-abi-mixed-link#src:tools/compiler_srchash.sh` GREEN at 24a4733f5bff (tier full) and did NOT close this: this is a repeat stub (`regression-test-c-abi-mixed-link-compiler-srchash-2`, not `regression-test-c-abi-mixed-link-compiler-srchash`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
