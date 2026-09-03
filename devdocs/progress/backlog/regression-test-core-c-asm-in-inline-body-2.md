---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 7 of 3 is `python3 tools/ast_slot_overloads.py --self-check`. The job's own `src` (`test/c_asm_in_inline_body.c`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_asm_in_inline_body.c@2 at 8000b96eab36 in step 7/3, `python3 tools/ast_slot_overloads.py --self-check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T15:27:51Z
- **Test source:** test/c_asm_in_inline_body.c tools/expect_same.sh +1
- **Failing step:** line 7 of 3 of the job's recipe; it names `tools/ast_slot_overloads.py`.
  ```
  python3 tools/ast_slot_overloads.py --self-check
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/c_asm_in_inline_body.c@2'` at 8000b96eab368edf9befedfab20021249eaff158

## Range
> **The named sha `8000b96eab36` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `8000b96eab36`, last good `0975f200bd17`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-748500/c_asm_inline26_o3  [code=65304B  data=12880B  bss=72856B  procs=831]
ast_slot_overloads: self-check OK — an injected payload write into AN_SEQ's Right is reported.
ast_slot_overloads: the slot-write census has CHANGED. If a new kind parks a non-node in ASTLeft/ASTRight, add it to ASTLeftIsChild/ASTRightIsChild in compiler/ast_arena.inc; then re-run with --update.
  --- expected
  +++ measured
  @@ -237,6 +237,7 @@
   AN_ARG Left vrCountLit
   AN_ARG Left vrIdent
   AN_ARG Left vtNameArg
  +AN_ARG Left wCastNode
   AN_ARG Left wIdentNode
   AN_ARG Left wNode
   AN_ARG Left withNode
  @@ -1036,6 +1037,7 @@
   AN_PTR_CAST Left CurASTNode
   AN_PTR_CAST Left node
   AN_PTR_CAST Left operand
  +AN_PTR_CAST Left wIdentNode
   AN_PTR_CAST Right -1
   AN_PTR_CAST Right castProcSig
   AN_RAISE Left valNode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
