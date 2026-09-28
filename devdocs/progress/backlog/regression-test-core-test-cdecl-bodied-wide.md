---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 3 of 21, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_wide.pas `, which names `test/test_cdecl_bodied_wide.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cdecl_bodied_wide.pas@2 at b1f2b7d8812d in step 3/21, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_wide.pas…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T06:12:23Z
- **Test source:** test/test_cdecl_bodied_wide.pas tools/expect_same.sh +2
- **Failing step:** line 3 of 21 of the job's recipe; it names `test/test_cdecl_bodied_wide.pas tools/expect_same.sh tools/run_target.sh`.
  ```
  if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/test_cdecl_bodied_wide.pas /tmp/test_cdecl_wide_rv32 && \ tools/expect_same.sh riscv32/test_cdecl_wide "$(tools/run_target.sh riscv32 /tmp/test_cdecl_wide_rv32)" "CDECL-WIDE OK checks=3"; \ else \ echo "===
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cdecl_bodied_wide.pas@2'` at b1f2b7d8812dce14468da84ec8e1e0e867f3c412

## Range
> **The named sha `b1f2b7d8812d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b1f2b7d8812d`, last good `9a245b91c409`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:71: error: incompatible types: @Cb10 uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:73: error: incompatible types: @Cb10 uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
(tail)
ok: /tmp/testmgr-scratch-426107/test_cdecl_wide_i386  [code=19146B  data=4720B  bss=35280B  procs=159  codeseg=20300B]
pascal26:71: error: incompatible types: @Cb10 uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:73: error: incompatible types: @Cb10 uses the Pascal convention but the procedural type uses cdecl -- declare both the same way

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
