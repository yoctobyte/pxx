---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 7 of 14 is `python3 tools/ast_slot_overloads.py --self-check`. The job's own `src` (`test/c_asm_in_inline_body.c`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_asm_in_inline_body.c@2 at 4fe0e6505042 in step 7/14, `python3 tools/ast_slot_overloads.py --self-check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T13:19:07Z
- **Test source:** test/c_asm_in_inline_body.c tools/expect_same.sh +2
- **Failing step:** line 7 of 14 of the job's recipe; it names `tools/ast_slot_overloads.py`.
  ```
  python3 tools/ast_slot_overloads.py --self-check
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_asm_in_inline_body.c@2'` at 4fe0e65050422843c9eedf09a383822774dc54b0

## Range
> **The named sha `4fe0e6505042` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fe0e6505042`, last good `3cd9c8f8251b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-631581/c_asm_inline26_o3  [code=65304B  data=12928B  bss=76520B  procs=868]
ast_slot_overloads: self-check OK — an injected payload write into AN_SEQ's Right is reported.
ast_slot_overloads: the slot-write census has CHANGED. If a new kind parks a non-node in ASTLeft/ASTRight, add it to ASTLeftIsChild/ASTRightIsChild in compiler/ast_arena.inc; then re-run with --update.
  --- expected
  +++ measured
  @@ -170,6 +170,7 @@
   AN_ARG Left keyNode
   AN_ARG Left kindNode
   AN_ARG Left kwDictNode
  +AN_ARG Left kwLitNode
   AN_ARG Left kwNone
   AN_ARG Left kwVal
   AN_ARG Left l1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
