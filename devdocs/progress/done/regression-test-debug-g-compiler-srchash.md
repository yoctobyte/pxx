---
prio: 70
track: A
---

> **Track A from the job NAME `test-debug-g`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-debug-g#src:tools/compiler_srchash.sh at 5d083bd91f9a in step 1/2, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$liv…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T10:31:31Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$livesrc" != "$stampsrc" ]; then \ echo "compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has."; \ if [ -z "$stampsrc" ]; then \ echo " stamp sources: <none
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-debug-g#src:tools/compiler_srchash.sh'` at 5d083bd91f9acb8aba5da9f8893a47cfe0223561

## Range
> **The named sha `5d083bd91f9a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5d083bd91f9a`, last good `68c168230560`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  e1a707c6b8f26d56792be74f7134217d0f88a3793afef9fbecf17cc77a4dad5a
A stamp NEWER than sources it does not describe is how this step
printed 'verified' three times in one day without building anything.
Recover with:  rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-03 — auto-closed by the seven watcher: `test-debug-g#src:tools/compiler_srchash.sh` passes at 71a66c7d1437 (tier native); it was red at 5d083bd91f9a. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
