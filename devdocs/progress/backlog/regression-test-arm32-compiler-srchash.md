---
prio: 70
track: A
---

> **Track A from the job NAME `test-arm32`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-arm32#src:tools/compiler_srchash.sh at b29428afe251 in step 1/1, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T17:22:50Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ -z "$livesrc" ]; then \ echo "tools/compiler_srchash.sh produced NO source hash, so this check cannot run."; \ echo " An empty result means 'could not measure', never 'measured and they
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-arm32#src:tools/compiler_srchash.sh'` at b29428afe251160ab130ead03f9132d3345e778a

## Range
> **The named sha `b29428afe251` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b29428afe251`, last good `95fc8aff2016`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: deadbeef
  tree sources:  2c26ecae2d8e5fa3a75cd41bdf9df7033d50b5f3594ff92edadba9fb4de89eec
  Same 215 files on both sides, so a hashed file's CONTENTS changed.
  Nothing untracked or modified locally, so no stray file explains it:
  this stamp was written for a DIFFERENT TREE. Usual cause is a pull
  -- or a sync, which pulls -- with no rebuild after it.
A stamp NEWER than sources it does not describe is how this step
printed 'verified' three times in one day without building anything.
Recover with:  rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
