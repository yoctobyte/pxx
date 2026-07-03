# imm-fold: constant BINOP operand into the instruction immediate (-O1, x86-64)

- **Type:** feature (codegen — emitter peephole) — Track A
- **Status:** working
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-optimization-levels]] — the next emitter-side (§3b,
  x86-64) peephole after passes 1-4. Emitter-side, not IR: it is about the x86-64
  instruction *encoding* (immediate operand form), so it does not lift to a
  shared IR pass.

## What

Pass 1 already loads a constant right operand into `rcx`
(`mov rcx, imm; <op> rax, rcx`). For arithmetic/logic ops that have an
`rax, imm32` encoding, fold the constant straight into the instruction and
drop the `rcx` load entirely:

```
mov rcx, imm32 ; add rax, rcx      ->     add rax, imm32
```

Removes one instruction (5-7 bytes) per constant arithmetic/logic operand.
Frequent in the compiler (`x + k`, `x - k`, masks, pointer+offset), so it should
show on the self-compile.

## Scope (safe subset)

Fast path at the top of `IR_BINOP` (ir_codegen.inc), gated `OptLevel >= 1`, when
the right operand is `IR_CONST_INT` fitting imm32 and the op is one of:

| op | encoding |
|----|----------|
| `+` | `add rax, imm32` = `48 05 id` |
| `-` | `sub rax, imm32` = `48 2D id` |
| `and` | `and rax, imm32` = `48 25 id` |
| `or` | `or rax, imm32`  = `48 0D id` |
| `xor` | `xor rax, imm32` = `48 35 id` |
| `*` | `imul rax, rax, imm32` = `48 69 C0 id` |

All sign-extend imm32 to 64 bits, exactly matching pass 1's
`mov rcx, imm32 (sign-ext); <op> rax, rcx` — so the result is bit-identical, no
width fixup needed (these ops operate on the full `rax` and downstream truncates
to the result type, unchanged).

**Excluded:** float and `tyAnsiString` results (guarded — those take the
ucomisd / concat paths); comparisons (leave to the `cmp rax,rcx` / compare-into-
branch-fusion path); `div`/`mod` (no imm form); shifts (the shift path's
`<8-byte` width fixup would have to be replicated — separate work, same hazard
noted for strength reduction).

## Gates

- `-O0` self-host fixedpoint byte-identical (gated `OptLevel>=1`).
- `make test-opt` differential corpus + `-O1` fixedpoint.
- Full `make test` under an `-O1`-built compiler.
- `make benchmark-opt-levels` + hyperfine self-compile delta recorded here.

## Related

- [[feature-optimization-levels]] (umbrella + log), passes 1-4 (this extends
  pass 1's const-operand handling).

## Log
- 2026-07-03 — opened + taken. Implementing the arith/logic imm32 fast path.
- 2026-07-03 — **DONE.** Fast path landed at the top of IR_BINOP (ir_codegen.inc),
  gated OptLevel>=1, `Exit` after emit (no post-case cleanup in IREmitNode).
  Fires meaningfully: -O1 self-code 3496244 -> 3466764 B (~29KB), -O1 compiler
  binary 3.61MB -> 3.57MB.
  - Gates: `make test-opt` green (+ -O1 fixedpoint); -O0 self-host fixedpoint
    byte-identical (sacred); full `make test` under an -O1-built compiler
    EXIT=0.
  - **Benchmark (hyperfine):** isolated vs pre-imm-fold -O1 = 1.01x (within
    noise) — this is a SIZE/icache win, speed-neutral (the dropped `mov rcx,imm`
    is cheap + latency-hidden). Whole -O arc `benchmark-opt-levels`: -O1-built
    self-compiles ~1.3-1.5x faster than -O0-built (4.47s vs 6.45s this run; the
    O0 baseline is machine-load-noisy) and ~12% smaller (3.57MB vs 4.08MB).
  - Folded into the -O1-built pin (transparent as always).
