---
prio: 70
track: A
---

> **Track A from the job NAME `test-debug-g`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-debug-g#src:tools/compiler_srchash.sh at 7e5a0470a6b2 in step 1/2, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$liv…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T04:48:59Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$livesrc" != "$stampsrc" ]; then \ echo "compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has."; \ if [ -z "$stampsrc" ]; then \ echo " stamp sources: <none
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-debug-g#src:tools/compiler_srchash.sh'` at 7e5a0470a6b2fc7c8f66312889b1fd92c17c5443

## Range
> **The named sha `7e5a0470a6b2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7e5a0470a6b2`, last good `147b8a2ac642`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  f9f7533766fa66785a4f5eb9712841e7af5d1eef8373cf5289eeb9c79eb02ced
A stamp NEWER than sources it does not describe is how this step
printed 'verified' three times in one day without building anything.
Recover with:  rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
