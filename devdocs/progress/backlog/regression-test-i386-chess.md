---
prio: 70
track: A
---

> **Track A from the job NAME `test-i386`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`examples/chess/chess.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-i386#src:examples/chess/chess.pas at 33bf8f7badd4 in step 1/2, `./compiler/pascal26 --target=i386 examples/chess/chess.pas /tmp/chess_i386` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T14:03:28Z
- **Test source:** examples/chess/chess.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `examples/chess/chess.pas`.
  ```
  ./compiler/pascal26 --target=i386 examples/chess/chess.pas /tmp/chess_i386
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-i386#src:examples/chess/chess.pas'` at 33bf8f7badd42c3f945ebc72592e56401661d230

## Range
> **The named sha `33bf8f7badd4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `33bf8f7badd4`, last good `bb18f83c859e`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:147: error: too many subscripts for array
(tail)
pascal26:147: error: too many subscripts for array
  near: [ sq ] . kind , >>> sq ] ; 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
