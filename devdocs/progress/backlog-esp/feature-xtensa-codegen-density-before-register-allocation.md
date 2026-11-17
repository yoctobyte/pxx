---
track: ESP
tags: [xtensa, codegen, size, register-allocation, gibux]
prio: 10
type: feature
blocked-by: []
summary: "pxx's xtensa code is about 6x gcc -O2 on a simple loop (about 160 bytes against 27), and the pxx-built Gibux kernel boots in 480 ms on the S3 where gcc's boots in 39 ms. The owner asked (relayed by pxx2) for register allocation for xtensa, then riscv32, then the density .n forms, then literal pool sharing. Most of the bytes come from expression emission, not from allocation, so this ticket stages the work: leaf operands loaded straight into a scratch register, fused compare-and-branch, increments without an address temporary, and only then scalar locals kept in registers."
status: backlog
owner: unassigned
---

# xtensa: expression codegen first, then register-resident locals

## Measured (2026-11-17, compiler 2498727eef3e)
`int f(int a,int b){int s=0,i;for(i=0;i<a;i++)s+=i*b;return s;}` built with `--target=esp32s3 --freestanding --emit-obj`: pxx gives about 160 bytes and gcc -O2 gives 27 (gcc also uses the zero-overhead `loop`). The waste in the pxx code, in order of bytes:

1. **Push/pop of the left operand around every binary op.** The pattern is `s32i a2,[sp]; <right into a2>; mov a3,a2; l32i a2,[sp]`, even when the right side is a constant or a plain local. Fix: if the right operand is a leaf (constant, local, parameter), load it directly into a3. This is the codegen's own "simple operand" test.
2. **Comparisons materialise 0/1.** They build `movi 1; bxx; movi 0`, then `sub`, `beq` against 0, `bne`/`j`/`j`. Fix: a condition in a branch context emits a single `bxx` (`blt`/`bge`/`beq`/`bne`/`bltu`/`bgeu`, plus the `bxxi`/`beqz` forms when the right side is a small constant or zero).
3. **`i++` / `x += c` on a local** goes through an address temporary and three stack slots. Fix: `l32i; addi; s32i` on the slot.
4. **Register-resident scalar locals.** Locals whose address is never taken live in a10..a15 (windowed; they are callee-saved by the window) for the whole procedure. This is the actual register allocation.

Measure each step with qemu executed-instruction counts and text size on test/c_xtensa_* plus the Gibux kernel. Wall clock is layout noise (see the C3 memory). pxx2's S3 board is available for silicon numbers.

After xtensa: the same steps for riscv32, then the density `.n` forms, then literal pool sharing.
