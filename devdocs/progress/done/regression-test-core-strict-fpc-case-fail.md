---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 6 of 15, `! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1`, which names `test/test_record_class_var_fail.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 7 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/strict_fpc_case_fail.pas at f2c6ff3288b4 in step 6/15, `! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T18:04:58Z
- **Test source:** test/strict_fpc_case_fail.pas test/test_record_self_field_fail.pas +5
- **Failing step:** line 6 of 15 of the job's recipe; it names `test/test_record_class_var_fail.pas`.
  ```
  ! ./compiler/pascal26 test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/strict_fpc_case_fail.pas'` at f2c6ff3288b407ca08ee7e469f4b2a8b56f98972

## Range
> **The named sha `f2c6ff3288b4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f2c6ff3288b4`, last good `7867c5481c01`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Measured 2026-09-05 (frankH): this row SURVIVED the revert of `4760474da`

Not a verdict on the cause, just the one fact that decides whether this ticket
is already closed by someone else's work.

Seven's RED at `f2c6ff3288b4` carried eight new-reds, and the other seven were
one class -- assignment/overload resolution into `Pointer`, from `4760474da`,
which frankB reverted in `2d6bfadd6` after reproducing four of them directly at
HEAD. **This row is not in that class and the revert did not fix it.**

Discriminator, chosen so it cannot be confused with a stale binary: the **v404
pin** (`stable_linux_amd64/default/pinned`, sha256 `fe1e9c37d322`, pinned from
tree `5b5fdb0b3`, which has `2d6bfadd6` as a verified ancestor) compiles
`test/test_record_class_var_fail.pas` successfully -- rc=0, where the recipe
requires a refusal naming `class var is not allowed in a record type`. A
compiler built at HEAD does the same. So the red is reproducible on a
post-revert tree from two independently built binaries.

**Read the ticket's own warning before bisecting**, because it applies here more
than usual: this expectation records a REFUSAL, and a feature landing makes its
own refusal test go red while the bisect converges on it correctly. `class var`
inside a record either became supported deliberately or stopped being refused by
accident, and those two need opposite fixes -- one edits the test, one edits the
compiler. Nobody has established which, and I did not: I hit this row while
gating an unrelated change, measured only enough to prove it was not mine, and
am recording that rather than leaving the next reader to redo it.

Note also that `test-core` stops at the FIRST failing recipe, so while this row
is red every row after step 6 of 15 is UNVERIFIED rather than green. `make -k`
is the way to see past it.
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8727b1907.
