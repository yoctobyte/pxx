---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 7 of 3 is `python3 tools/ast_slot_overloads.py --self-check`. The job's own `src` (`test/c_asm_in_inline_body.c`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_asm_in_inline_body.c@2 at 2d6e7d5c26db in step 7/3, `python3 tools/ast_slot_overloads.py --self-check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T10:45:33Z
- **Test source:** test/c_asm_in_inline_body.c tools/expect_same.sh +1
- **Failing step:** line 7 of 3 of the job's recipe; it names `tools/ast_slot_overloads.py`.
  ```
  python3 tools/ast_slot_overloads.py --self-check
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_asm_in_inline_body.c@2'` at 2d6e7d5c26dbf04eb318b4fb509a672903fde6eb

## Range
> **The named sha `2d6e7d5c26db` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2d6e7d5c26db`, last good `bb524e1abd1f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-282022/c_asm_inline26_o3  [code=65304B  data=12880B  bss=72856B  procs=830]
ast_slot_overloads: self-check OK — an injected payload write into AN_SEQ's Right is reported.
ast_slot_overloads: the slot-write census has CHANGED. If a new kind parks a non-node in ASTLeft/ASTRight, add it to ASTLeftIsChild/ASTRightIsChild in compiler/ast_arena.inc; then re-run with --update.
  --- expected
  +++ measured
  @@ -382,6 +382,7 @@
   AN_ASSIGN Right ASTRight[pairNode]
   AN_ASSIGN Right AllocNode(AN_BINOP)
   AN_ASSIGN Right AllocNode(AN_INT_LIT)
  +AN_ASSIGN Right CLIArrElem[cliBase + ei]
   AN_ASSIGN Right CNormalizeToBool(IntToTypeKind(ASTTk[left]), ASTRight[node])
   AN_ASSIGN Right CNormalizeToBool(declTk, ASTRight[asn])
   AN_ASSIGN Right CPromoteCharTo(IntToTypeKind(ASTTk[left]), rhs)
  @@ -424,7 +425,6 @@
   AN_ASSIGN Right addNode
   AN_ASSIGN Right addrNode
   AN_ASSIGN Right argAST
  -AN_ASSIGN Right arrElems[ei]
   AN_ASSIGN Right atDflt
   AN_ASSIGN Right bNode
   AN_ASSIGN Right baseNode

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — auto-closed by the seven watcher: `test-core#src:test/c_asm_in_inline_body.c@2` passes at 6f6ec7b36e0f (tier native); it was red at 2d6e7d5c26db. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
