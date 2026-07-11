# 2026-07-11 — -O3 W1 operand scheduler + W2 loop residency

Machine: dev box (x86-64). Compiler: master @ 33281797, self-hosted frozen
build. All comparisons are the SAME compiler binary compiling/building at
`-O2` (the proven default) vs `-O3` (the experimental tier that carries the
new passes). Every pair verified output-identical before timing.

## What -O3 adds (feature-opt-o3-register-pressure, all x86-64-only)

1. **Binop operand scheduler** (W1): mirror (leaf left loads after complex
   right), r8/r9 scratch for call-free right subtrees, r12/r13 callee-saved
   scratch for call-bearing right subtrees; same transforms on fused-compare
   operands.
2. **Leaf-index fold** (W1): const array index → one `add rax, disp`;
   leaf-sym index → load/scale in rcx. Killed 20k of 34k pop-rcx dances in
   the self-compile image.
3. **Last-call-arg collapse** (W1): direct, virtual and indirect internal
   calls keep the final argument in rax (`mov <reg>, rax`) instead of
   push/pop.
4. **Loop-local residency** (W2): up to two loop-hot scalar locals/params
   resident in r12/r13 (kills the loop-carried store-forward chain).
5. **Float loop residency** (W2): up to two loop-hot tyDouble vars in
   xmm8/xmm9 in provably call-free bodies.

## Results (hyperfine, outputs byte/text-identical)

| workload | -O2 | -O3 | speedup |
|---|---|---|---|
| mandelbrot --bench 400x300 (float kernel) | 83.7 ms | 69.4 ms | **1.21×** |
| raytracer (call-heavy float) | 17.5 ms | 16.1 ms | **1.09×** |
| compiler self-compile (memory-bound) | 3.41 s | 3.27 s | **1.04–1.05×** |
| sieve (bit-twiddling, memory-bound) | 67 ms | 66 ms | 1.01–1.03× |

Self-compile instruction mix: 940.9k → 860.5k emitted instructions
(**−8.5%**), `pop rcx` 34.4k → 14.2k, `pop rdi` 31.1k → 9.4k, `push rax`
99.9k → 44.9k. Code size −3.1%.

## Findings

- The compiler itself is **memory-bound**: −8.5% instructions buys only ~4-5%
  wall. Judge codegen passes on compute benchmarks, not self-compile.
- OoO hides plain L1 reloads (why regcall phase-2 was rejected) but NOT
  loop-carried store-forward chains — loop-var residency is the form of
  "kill frame traffic" that pays.
- Raytracer's ceiling is its non-inlined Vec helper calls: bodies with calls
  can't hold floats in caller-saved xmm8/9. Inline expansion of small leaf
  float routines is the next unlock.

Also fixed today (found while designing W2): the shipping -O2 default
miscompiled resident params read in exception handlers after a raise
(longjmp rolls back r14/r15) — `bug-a-o2-resident-param-stale-after-longjmp`,
re-pinned as v195.
