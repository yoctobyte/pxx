---
track: ESP
tags: [xtensa, codegen, size, register-allocation, nilix]
prio: 10
type: feature
blocked-by: []
summary: "pxx's xtensa code is about 6x gcc -O2 on a simple loop (about 160 bytes against 27), and the pxx-built Nilix kernel boots in 480 ms on the S3 where gcc's boots in 39 ms. The owner asked (relayed by pxx2) for register allocation for xtensa, then riscv32, then the density .n forms, then literal pool sharing. Most of the bytes come from expression emission, not from allocation, so this ticket stages the work: leaf operands loaded straight into a scratch register, fused compare-and-branch, increments without an address temporary, and only then scalar locals kept in registers."
status: backlog
owner: unassigned (steps 1-3 done 2026-11-19; step 4 is the owner's call)
---

# xtensa: expression codegen first, then register-resident locals

## Measured (2026-11-17, compiler 2498727eef3e)
`int f(int a,int b){int s=0,i;for(i=0;i<a;i++)s+=i*b;return s;}` built with `--target=esp32s3 --freestanding --emit-obj`: pxx gives about 160 bytes and gcc -O2 gives 27 (gcc also uses the zero-overhead `loop`). The waste in the pxx code, in order of bytes:

1. **Push/pop of the left operand around every binary op.** The pattern is `s32i a2,[sp]; <right into a2>; mov a3,a2; l32i a2,[sp]`, even when the right side is a constant or a plain local. Fix: if the right operand is a leaf (constant, local, parameter), load it directly into a3. This is the codegen's own "simple operand" test.
2. **Comparisons materialise 0/1.** They build `movi 1; bxx; movi 0`, then `sub`, `beq` against 0, `bne`/`j`/`j`. Fix: a condition in a branch context emits a single `bxx` (`blt`/`bge`/`beq`/`bne`/`bltu`/`bgeu`, plus the `bxxi`/`beqz` forms when the right side is a small constant or zero).
3. **`i++` / `x += c` on a local** goes through an address temporary and three stack slots. Fix: `l32i; addi; s32i` on the slot.
4. **Register-resident scalar locals.** Locals whose address is never taken live in a10..a15 (windowed; they are callee-saved by the window) for the whole procedure. This is the actual register allocation.

Measure each step with qemu executed-instruction counts and text size on test/c_xtensa_* plus the Nilix kernel. Wall clock is layout noise (see the C3 memory). pxx2's S3 board is available for silicon numbers.

After xtensa: the same steps for riscv32, then the density `.n` forms, then literal pool sharing.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).

## Steps 1-3 done (2026-11-19, pxx Rainyday seat)

- **Step 1, leaf operands.** XtLeafOperand / EmitLeafXtensa: a right operand
  that is an integer constant or a scalar variable is loaded straight into a3
  (EmitLoadVarRegXtensa, the old EmitLoadVarXtensa with a destination; it
  touches only rd, a8, a9). `x + k` / `x - k` with |k| <= 127 is one addi.
- **Step 2, compare and branch.** IR_JUMP_IF_FALSE on a 32-bit integer
  comparison (XtBranchCompare: not string, float, 64-bit or `in`) is the
  comparison's own bxx over the J (XtEmitBranchIfTrue), signed or unsigned.
  `c == 0` / `c != 0` of a comparison, which is how the C front end spells
  every condition, folds into c's branch (negated through the r field's bit 3).
- **Step 3, increments.** Shared IR (ir.inc): `v++` / `v--` / `++v` whose
  value is unused (a statement, a for step, a comma's left operand) on a
  plain scalar variable lowers to `v = v + step` (IRLowerForEffect), no
  address temp and no old-value slot. Every backend gets it.

Measured: the loop above is 41 instructions (was 74), its body 18 (about
50). Rainyday S3 kernel (290661b, esp32s3 profile) .text 1,344,586 ->
1,091,557 bytes (-18.8%); it boots and runs init in QEMU, "halted after"
457 -> 376 ms (wall, noisy).

Checked: make test-xtensa (whole target; the long backward-jump row's
generated body grew from 3000 to 6000 tests because it fell under 128 KiB),
c-testsuite 220/220 on x86-64 and on hosted xtensa call0, both as latest;
tools/check_xtensa_density.py (new, test-core): test/c_density_branch_incdec.c
against gcc on call0 and windowed, and the loop at most 45 instructions.

## Follow-ups done (2026-11-19, same seat)

- xtensa: `jump_if_false L; jump M; L:` (every C loop head) is one inverted
  branch over `j M` (XtJumpThenLabel); a jump to the very next instruction
  (an `if` without `else`) is not emitted (XtLabelFollows); against the
  constant 0 the BRI12 forms beqz/bnez/bltz/bgez (EncodeXtensaBZ), and a
  plain truth test is bnez instead of movi + bne.
- riscv32: steps 1 and 3 were already there (leaf operands through
  LeafLoadSymFoldsRISCV32; ++ now through the shared IR). Step 2 existed as
  Rv32EmitCmpBranch but missed the C front end's `c == 0` / `c != 0`
  wrapper and materialised c with slt; it now folds (Rv32EmitCmpBranchOn).
  The ticket's loop: 48 -> 47 on esp32c3.
- Measured: loop f 41 -> 40 on xtensa; Rainyday S3 kernel .text 1,091,557
  -> 1,067,424 (-20.6% against the 1,344,586 of the start); boots in QEMU.
  make test-xtensa and test-riscv32 green; c-testsuite 220/220 on hosted
  xtensa and riscv32, as latest.

## Follow-ups done, second round (2026-11-19, same seat)

- 3187230470: a commutative binop (+ * and or xor) with a leaf left and a
  computed, effect-free right emits the right first and loads the left into
  a3, so `s += i * b` no longer spills. Loop f 40 -> 37.
- c277872bbc: compare against a constant in b4const / b4constu is one
  beqi/bnei/blti/bgei/bltui/bgeui (a > k, a <= k take k+1). S3 kernel
  .text 1,066,020 -> 1,064,144.
- 1c91859cdd: a forward conditional branch goes straight to its label when
  it reaches (XtBrFix*, checked after the pass; one that does not reach
  sets XtBrFar[IR index] and the body re-emits with the skip-over form).
  Loop f 37 -> 36; S3 kernel .text 1,064,144 -> 1,036,909 (-22.9% against
  the start). The retry exposed a latent call0 bug: ProcSweepThunkAddr
  survived into the next pass (fixed; test_xtensa_sweep_thunk_relax).

Still open before step 4: the riscv32 C3 kernel measured.
