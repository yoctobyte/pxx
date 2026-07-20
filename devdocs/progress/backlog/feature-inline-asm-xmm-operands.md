---
prio: 55  # auto — blocks all float and vector asm; gates the per-ISA optimization story
track: A
---

# Inline asm cannot express float or vector code (no xmm operands, no packed SSE, no VEX, no cpuid)

- **Type:** feature — **Track A** (`compiler/asmfront.inc`, `compiler/asmtext.inc`,
  `compiler/asmtext_386.inc`; the asm frontend).
- **Status:** backlog — filed 2026-07-20, **rescoped the same day** (the first
  version of this ticket said "plausibly a small change" — that was wrong, see
  Correction below).
- **Found by:** Track E, building the Mandelbrot demos
  ([[feature-demo-mandelbrot-asm-autozoom]],
  [[feature-demo-mandelbrot-gui-threaded]]) — the goal there is a per-target,
  per-ISA-level optimized iteration kernel, which is not expressible today.

## Correction to the original scope

The first version of this ticket claimed only `AsmRegLookup` was missing xmm
names and everything downstream was ready. That is true for **scalar** SSE and
false for everything else. A survey of `asmtext.inc` (104 mnemonics total):

| group | status |
| --- | --- |
| scalar SSE: `movsd movss addsd subsd mulsd divsd addss subss mulss divss comisd ucomisd cvtsd2ss cvtss2sd xorps xorpd pxor` | **encoded** |
| `movq` xmm↔gp/mem bridge, `cvtsi2sd`, `cvttsd2si` | **encoded** |
| packed SSE2: `movapd movupd mulpd addpd subpd divpd cmppd andpd andnpd orpd sqrtpd movmskpd unpcklpd unpckhpd shufpd` | **all missing** |
| AVX / VEX encoding of any of the above (`vmulpd vaddpd vcmppd vmovapd vbroadcastsd`) | **all missing** — no VEX prefix emitter at all |
| FMA (`vfmadd231pd` …) | **missing** |
| CPU feature discovery: `cpuid`, `xgetbv` | **missing** |
| `rdtsc` | missing (minor, but the obvious companion) |
| xmm register OPERANDS in inline asm (`AsmRegLookup` in `asmfront.inc`) | **missing** |

So the work is: operand naming (small) + a packed-SSE2 encoder arm (moderate) +
a VEX prefix emitter and the AVX mnemonic set (the real chunk) + `cpuid`/`xgetbv`
(small, but they gate any runtime dispatch).

## Symptoms

```
pascal26: error: asm: unknown instruction: xorpd ()      { operands failed to parse }
pascal26: error: asm: unknown instruction: cpuid ()      { not in the mnemonic table }
```

## What already exists and should be reused

- `compiler/asmenc.inc` (~line 119) already resolves `xmm0..xmm15`, flagging them
  **size 16** — the convention the encoders expect. `asmfront.inc`'s
  `AsmRegLookup` is a second, GP-only table; the two should converge.
- `compiler/asmtext.inc` (~line 596ff) already has the scalar SSE prefix/opcode
  dispatch (`ssePfx` / `sseOp`, with `x64_sse_rr` / `x64_sse_rm`). Packed ops are
  the same encoders with prefix `$66` and no `F2/F3`, so that arm is largely
  parameter changes, not new machinery.
- `compiler/asmtext_386.inc` has the 32-bit counterpart.
- `compiler/asmdisasm_x64.inc` already disassembles the scalar forms; extend
  alongside so `--disasm` output stays useful.

## Suggested phasing

1. **xmm operands** in `asmfront.inc` (size 16), so the ALREADY-ENCODED scalar
   SSE becomes reachable from Pascal inline asm. Unblocks a scalar-double
   escape kernel on its own — immediate, visible payoff.
2. **`cpuid` + `xgetbv`.** Small, and they unblock runtime ISA dispatch even
   before any vector op exists (a program can then pick between a GP kernel and
   a scalar-SSE kernel).
3. **Packed SSE2** (`$66` prefix over the existing scalar dispatch) —
   `movapd/movupd/addpd/subpd/mulpd/divpd/cmppd/andpd/movmskpd/unpcklpd/shufpd`.
   2-wide double kernels become writable.
4. **VEX prefix emitter + AVX/AVX2** (`v*pd`, `vbroadcastsd`), then FMA. 4-wide.
   This is the largest piece and is where a real design decision lives (2-byte vs
   3-byte VEX selection, and how much of the operand model needs a third source
   operand for the non-destructive `v` forms).

Phases 1–3 are worth landing on their own; phase 4 can wait.

## Cross-target note

The same question exists for the other backends' vector units — aarch64 NEON
(`fmul.2d`, `fcmgt`), arm32 VFP/NEON, and their register files (`d0..d31`,
`v0..v31`, `q0..q15`) are equally unreachable from inline asm. Per Track O's
rule, per-backend effort is x86-64 + aarch64 only; the others can stay
portable-fallback indefinitely. Worth deciding whether NEON rides along with
phase 3/4 or gets its own ticket.

## Consumers waiting on this

- `examples/mandelbrot/mandelkernel.pas` — the per-ISA kernel unit. Its SSE2 and
  AVX2 arms are written and committed but compiled out behind `PXX_ASM_SIMD`;
  the define exists ONLY because of this ticket and should be deleted (not
  redefined) once phases 1–4 land. That unit is the acceptance test that matters.
- [[feature-demo-mandelbrot-asm-autozoom]] shipped an Int64 Q4.28 GP-register
  kernel instead of the SSE2 double kernel it wanted.

## Acceptance

- `examples/mandelbrot/mandelkernel.pas` compiles with `PXX_ASM_SIMD` defined,
  its SSE2 and AVX2 kernels produce escape counts identical to the portable
  kernel over a grid, and `mandelbrot_gui`'s status line reports the dispatched
  ISA.
- Regression tests per phase (`test/test_asm_sse_scalar.pas`,
  `test/test_asm_cpuid.pas`, `test/test_asm_sse_packed.pas`,
  `test/test_asm_avx.pas`), each asserting encodings against `llvm-mc` the way
  `test_asm_emit_x64.pas` already does.
- The `xmm8–15` caller-save discipline in
  `devdocs/dev/optimization-architecture.md` holds for hand-written blocks.
- Track A gate: `make test` + self-host byte-identical.

## Links
[[feature-demo-mandelbrot-gui-threaded]] · [[feature-demo-mandelbrot-asm-autozoom]] ·
`compiler/asmfront.inc` (`AsmRegLookup`) · `compiler/asmtext.inc` (scalar SSE
dispatch to extend) · `compiler/asmenc.inc` (has the xmm names already).

## Log
- 2026-07-20 — Filed from Track E as "xmm operands missing".
- 2026-07-20 — **Rescoped** after surveying the mnemonic table: packed SSE, all
  of AVX/VEX, and `cpuid` are absent too, so this is a phased project rather
  than a small fix. Original estimate withdrawn.
