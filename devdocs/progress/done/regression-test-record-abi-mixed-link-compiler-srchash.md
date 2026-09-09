---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 25 is `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$l`. The job's own `src` (`tools/compiler_srchash.sh`, 5 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-record-abi-mixed-link#src:tools/compiler_srchash.sh at 3b5005e79ea4 in step 1/25, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T10:07:41Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +3
- **Failing step:** line 1 of 25 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$livesrc" ]; then \ echo "tools/compiler_srchash.sh produced NO source hash, so this check cannot run."; \ echo " An empty result means 'could not measure', never 'measured and they
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-record-abi-mixed-link#src:tools/compiler_srchash.sh'` at 3b5005e79ea4ff697f32ee50d711ef0dd34e8e5b

## Range
> **The named sha `3b5005e79ea4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3b5005e79ea4`, last good `b293f97bfa08`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  f6fbb8d4ad5d8cbff4072ab29aa03d3b66422ffc45673f17920fb45375b87d3e
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
- 2026-09-09 — auto-closed by the seven watcher: `test-record-abi-mixed-link#src:tools/compiler_srchash.sh` passes at 83ff073db213 (tier full); it was red at 3b5005e79ea4. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
