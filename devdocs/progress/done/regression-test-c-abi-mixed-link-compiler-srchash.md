---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 2 is `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$l`. The job's own `src` (`tools/compiler_srchash.sh`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-abi-mixed-link#src:tools/compiler_srchash.sh at f84be3fd43df in step 1/2, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-07T01:11:07Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +2
- **Failing step:** line 1 of 2 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$livesrc" ]; then \ echo "tools/compiler_srchash.sh produced NO source hash, so this check cannot run."; \ echo " An empty result means 'could not measure', never 'measured and they
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-c-abi-mixed-link#src:tools/compiler_srchash.sh'` at f84be3fd43df284d88b1636929c5ec547bffc4da

## Range
> **The named sha `f84be3fd43df` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f84be3fd43df`, last good `84c41d6ee630`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
sed: can't read compiler/.pascal26.fixedpoint: No such file or directory
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  7f9bafeabcd1863b4fa03820b210bb2290f2e5520a67a749ceb39b4890b8fae7
sed: can't read compiler/.pascal26.fixedpoint: No such file or directory
  Stamp predates the srccount field, so set-vs-contents cannot be told apart.
  It will be after the next rebuild.
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
- 2026-09-07 — auto-closed by the seven watcher: `test-c-abi-mixed-link#src:tools/compiler_srchash.sh` passes at 2b692bbb71b3 (tier full); it was red at f84be3fd43df. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
