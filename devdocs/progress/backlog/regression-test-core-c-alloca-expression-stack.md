---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 9 of 37, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/c_alloca_expression_stack.c`, which names `test/c_alloca_expression_stack.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_alloca_expression_stack.c at 9b0c07c2d5a8 in step 9/37, `if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/c_alloca_expression_stack.…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T17:29:23Z
- **Test source:** test/c_alloca_expression_stack.c tools/expect_same.sh +2
- **Failing step:** line 9 of 37 of the job's recipe; it names `test/c_alloca_expression_stack.c tools/expect_same.sh tools/run_target.sh test/c_vla.c`.
  ```
  if command -v qemu-riscv32 >/dev/null 2>&1; then \ ./compiler/pascal26 --target=riscv32 test/c_alloca_expression_stack.c /tmp/c_alloca_expr_rv >/dev/null || { echo "c_alloca_expression_stack riscv32 compile FAIL"; exit 1; }; \ tools/expect_same.sh riscv32/c_alloca_expr_rv "$(tools/run_target.sh risc
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_alloca_expression_stack.c'` at 9b0c07c2d5a8f1fe0ad12b4c13233cf0838ca54d

## Range
bad `9b0c07c2d5a8`, last good `e50bd2535f3f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-696977/c_alloca_expr26  [code=323352B  data=13648B  bss=76520B  procs=869]
expect_same: MISMATCH [riscv32/c_vla_rv]
--- expected
+++ actual
@@ -5,3 +5,4 @@
 36
 10
 24
+9 7 6

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-09 — the seven watcher saw `test-core#src:test/c_alloca_expression_stack.c` GREEN at ab1d60ab88f2 (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
