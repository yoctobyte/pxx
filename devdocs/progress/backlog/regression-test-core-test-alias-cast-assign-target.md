---
prio: 70
track: A
---

> **Track guessed as P from the FAILING STEP** — line 7 of 3, `if ./compiler/pascal26 test/test_setlength_cast_refusal.pas /tmp/test_slcastref26 2>&1 \ | grep -q 'SetLength expects a `, which names `test/test_setlength_cast_refusal.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_alias_cast_assign_target.pas at 91b4b77ec631 in step 7/3, `if ./compiler/pascal26 test/test_setlength_cast_refusal.pas /tmp/test_slcastref26 2>&1 \ | grep -q 'SetLength expects a…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T16:51:44Z
- **Test source:** test/test_alias_cast_assign_target.pas tools/expect_same.sh +1
- **Failing step:** line 7 of 3 of the job's recipe; it names `test/test_setlength_cast_refusal.pas`.
  ```
  if ./compiler/pascal26 test/test_setlength_cast_refusal.pas /tmp/test_slcastref26 2>&1 \ | grep -q 'SetLength expects a string variable'; then \ echo "ok: test_setlength_cast_refusal (int alias cast still refused)"; \ else \ echo "FAIL: SetLength(TI(i), n) is no longer refused -- the cast-drop widen
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_alias_cast_assign_target.pas'` at 91b4b77ec631e4027893233277450f576e3008fc

## Range
> **The named sha `91b4b77ec631` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `91b4b77ec631`, last good `5e2dcc37c253`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1627775/test_aliascast26  [code=69400B  data=4180B  bss=43788B  procs=136]
FAIL: SetLength(TI(i), n) is no longer refused -- the cast-drop widened past string types

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

> **RE-LANED T/P -> A by the coordinator, 2026-09-03, on COMMIT CONTENT, not on the failing step.** The only code commit between the last GREEN native (`5e2dcc37c253`) and this RED (`91b4b77ec631`) is `0dedfb86c` "fix(A): SetLength through a field, an element or a deref", which touches `Makefile`, `compiler/ir_codegen.inc` and the 386/aarch64/arm32/riscv32/xtensa arms plus `compiler/pasparser_stmt.inc`. The other five commits in the window touch no code at all. That is a suspect established by ref arithmetic with zero builds — it is NOT a measured cause, and the author (franka-29) has been told and may reject it.

> **This may not be a regression.** The alias-cast row fails on a REFUSAL grep (`SetLength expects a`), and `0dedfb86c` deliberately widened what `SetLength` accepts. A refusal test going red is exactly what an intended widening looks like; if that is what happened, the TEST is what needs updating and there is no defect here. Establish which before treating any of these three as a bug.
