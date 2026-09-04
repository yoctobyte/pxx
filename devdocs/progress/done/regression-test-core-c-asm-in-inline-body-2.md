---
prio: 70
track: T
status: done
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

## Log
- 2026-09-03 — the seven watcher saw `test-core#src:test/c_asm_in_inline_body.c@2` GREEN at addffd2608d3 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-c-asm-in-inline-body-2`, not `regression-test-core-c-asm-in-inline-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4b67ea324.

## Already fixed, by the author, in the commit that also stopped it recurring (frankA, 2026-09-04)

**The failing step is not about the C test.** Line 7 is
`python3 tools/ast_slot_overloads.py --self-check`, a tree-wide census of which
`(AST kind, slot)` pairs the compiler writes; the job's `src` names the C file
only because that is the job it happened to be a step of. Read the step, not the
slug.

### The drift, and who caused it

The census reported two new rows:

```
+AN_ARG       Left  wCastNode
+AN_PTR_CAST  Left  wIdentNode
```

Both are written by `compiler/pyparser.inc` (`ASTLeft[wCastNode] := wIdentNode`,
the width-truncating value cast in the NilPy clone-entry path), added by
`d49de34b6`, which did **not** update `test/ast_slot_writes.expected`. They are
legitimate CHILD writes, not payloads parked in a node slot, so the correct
response was to accept them — which is what the guard is for: it cannot tell the
two apart and asks a human.

### Fixed at `72c431bd9`, and its message says so unprompted

> `tools/gate.sh` now runs the AST slot-write census. `d49de34b6` (mine) added
> two legitimate child writes and left `test/ast_slot_writes.expected` stale, and
> the census only ran in `make test-core`, which the per-fix loop does not run.
> ... Snapshot updated after reading every row.

So the snapshot was updated **after reading every row**, not by a blind
`--update` — which is the failure mode that would have made this close dishonest.

### Why it should not come back a third time

This slug is the SECOND red on the same guard
([[regression-test-core-c-asm-in-inline-body]] was the first). The recurrence had
a structural cause: the census ran only in `make test-core`, which the per-fix
loop does not run, so any commit could leave it stale and only a full tier would
notice — hours later, attributed to whatever job happened to carry the step.
`72c431bd9` moved it into `tools/gate.sh`, verified here at `gate.sh:311-313`, so
it now runs in the loop that lands the change.

Verified at HEAD: `rc=0`, `OK — 96 (kind, slot) pairs written across the
compiler, every payload slot declared`, and the self-check's own positive control
(`an injected payload write into AN_SEQ's Right is reported`) passes.
