---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 3 of 8, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_narrow.pa`, which names `test/test_cdecl_bodied_narrow.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cdecl_bodied_narrow.pas@2 at b1f2b7d8812d in step 3/8, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_narrow.p…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T06:12:23Z
- **Test source:** test/test_cdecl_bodied_narrow.pas tools/expect_same.sh +1
- **Failing step:** line 3 of 8 of the job's recipe; it names `test/test_cdecl_bodied_narrow.pas tools/expect_same.sh tools/run_target.sh`.
  ```
  if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_narrow.pas /tmp/test_cdecl_narrow_rv32 && \ tools/expect_same.sh riscv32/test_cdecl_narrow "$(tools/run_target.sh riscv32 /tmp/test_cdecl_narrow_rv32)" "CDECL-NARROW OK checks=12"; \ else \
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cdecl_bodied_narrow.pas@2'` at b1f2b7d8812dce14468da84ec8e1e0e867f3c412

## Range
> **The named sha `b1f2b7d8812d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b1f2b7d8812d`, last good `9a245b91c409`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:119: error: incompatible types: @CbID uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
(tail)
ok: /tmp/testmgr-scratch-426107/test_cdecl_narrow_i386  [code=21097B  data=5328B  bss=35296B  procs=173  codeseg=24396B]
pascal26:119: error: incompatible types: @CbID uses the Pascal convention but the procedural type uses cdecl -- declare both the same way

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-28 — the borg watcher saw `test-core#src:test/test_cdecl_bodied_narrow.pas@2` GREEN at a8e99254ed4b (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
