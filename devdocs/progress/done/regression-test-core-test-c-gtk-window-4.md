---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_c_gtk_window.pas /tmp/test_c_gtk_window26`, which names `test/test_c_gtk_window.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_window.pas at 7867c5481c01 in step 1/2, `./compiler/pascal26 test/test_c_gtk_window.pas /tmp/test_c_gtk_window26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-05T17:58:16Z
- **Test source:** test/test_c_gtk_window.pas lib/pcl/gtk3_c.h
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_c_gtk_window.pas`.
  ```
  ./compiler/pascal26 test/test_c_gtk_window.pas /tmp/test_c_gtk_window26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_window.pas'` at 7867c5481c0126cd79daa92c74114b8dd3fc6ef3

## Range
> **The named sha `7867c5481c01` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7867c5481c01`, last good `b8e3b3010249`, 87 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: error: uses: unit source not found: gtk
(tail)
pascal26:2: error: uses: unit source not found: gtk
  near: program test_c_gtk_window ; uses gtk >>> ; function AutoQuit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a058097b7.

## Closed 2026-09-05 (frankB) — reproduce-clean at HEAD, full job, not just the failing step

Ran the ticket's own Repro line — `testmgr.py --tier native --job ...` — at HEAD,
not the sha it was filed against: **1/1 pass, testmgr GREEN.** The failing step
alone was also re-run and compiles. Both, because a ticket whose recorded
failure is step 1 of 2 can have step 2 fail for its own reasons, and "the
failing step passes" is a narrower claim than "the job passes".

**Cause, and it is mine.** These five `test_c_gtk*` rows plus the stackless one
read as STILL-RED to the watcher and were not unchanged: they were extra
instances of `4760474da` (my `AssignSideKind` / pointer-sink rule, which refused
every legal Char→PChar binding). Reverted in `2d6bfadd6`. A STILL-RED whose
CAUSE has changed is indistinguishable from background noise in the verdict
column, which is why they sat here after the revert had already fixed them.

**The lane was a guess and the guess is now moot.** The banner at the top of
this file says so itself: `track: P` was inferred from the failing step naming a
`.pas` file, and the ranker reads only the frontmatter. That put six auto-filed
regressions in the top rows of `ready --track P`. They are closed on evidence,
not re-laned — a re-lane would have moved a finished ticket to another queue.
