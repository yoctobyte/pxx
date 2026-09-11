---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$l`. The job's own `src` (`tools/compiler_srchash.sh`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:tools/compiler_srchash.sh at 6cf4d662b25d in step 1/1, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-11T03:04:36Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$livesrc" ]; then \ echo "tools/compiler_srchash.sh produced NO source hash, so this check cannot run."; \ echo " An empty result means 'could not measure', never 'measured and they
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:tools/compiler_srchash.sh'` at 6cf4d662b25d2745d07181d37f3da171b544db8f

## Range
> **The named sha `6cf4d662b25d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6cf4d662b25d`, last good `a515b921cca3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  1594f54643dcaf39f226a9a0433d85cea72f6676a5d64dd882b25e0303e8b862
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
