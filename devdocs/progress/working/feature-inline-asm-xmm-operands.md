---
prio: 55  # auto — blocks all float and vector asm; gates the per-ISA optimization story
track: A
owner: agent-an
---

# Inline asm cannot express float or vector code (no xmm operands, no packed SSE, no VEX, no cpuid)

- **Type:** feature — **Track A** (`compiler/asmfront.inc`, `compiler/asmtext.inc`,
  `compiler/asmtext_386.inc`; the asm frontend).
- **Status:** working
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

---

## 2026-08-14 — PHASE 1 DONE, and a scope correction: it was TWO gaps, not one

### The correction

This ticket's phase 1 says *"xmm operands in `asmfront.inc` (size 16), so the
ALREADY-ENCODED scalar SSE becomes reachable from Pascal inline asm."* That is
wrong, and the "Correction to the original scope" section above inherited the
same conflation: it lists the scalar-SSE row as **encoded** without saying
*where*.

There are **three** x86 encoders in this compiler, with three separate mnemonic
tables:

| file | drives | had scalar SSE? |
| --- | --- | --- |
| `asmfront.inc` | standalone `.asm` FILES, via `lib/asmcore` | n/a — its gap was the REGISTER table |
| `asmenc.inc` | Pascal inline `asm ... end` | **NO — zero SSE mnemonics** |
| `asmtext.inc` | compiler-emitted `EmitAsmX64` | yes, the 17 the ticket lists |

So the scalar SSE was encoded in the encoder that inline asm does **not** use.
Measured rather than assumed: `grep -c` for the scalar mnemonics gives **0** in
`asmenc.inc` and **17** in `asmtext.inc`. And the two gaps are in different
files from each other:

- `asmfront.inc`'s `AsmRegLookup` was a GP-only name table — that is the one the
  ticket names, and it affects `.asm` files, not inline asm;
- `asmenc.inc`'s operand parser already resolved `xmm0..15` (via `AsmRegNum`,
  size 16) and had done all along. Its missing piece was the MNEMONIC.

That is why the first attempt still failed with `asm: unknown instruction:
movsd` *after* the register table was fixed — the registers had never been the
inline-asm problem.

### What landed

1. **`asmfront.inc`: `AsmRegLookup` now delegates to `AsmRegNum`** instead of
   carrying a second hand-written table. `AsmRegNum` already resolves the whole
   register file including xmm at size 16, and `reg_rax..reg_r15` ARE 0..15
   (`asmcore_x64.pas`), so no translation is needed. A size filter (4/8/16)
   keeps the change to exactly "xmm is now nameable" — `AsmRegNum` also answers
   the 1- and 2-byte names, which this operand model has never accepted, and
   silently widening to them would be a second, unrelated change.
2. **`asmenc.inc`: a scalar-SSE arm**, deliberately the same prefix/opcode data
   as `asmtext.inc`'s (these are x86 facts, not a policy either encoder gets to
   pick):
   `movsd movss addsd addss subsd subss mulsd mulss divsd divss sqrtsd comisd
   ucomisd cvtsd2ss cvtss2sd xorpd xorps andpd pxor`, plus `cvtsi2sd`,
   `cvttsd2si` and `cvtsd2si`.

`cvtsd2si` is included on purpose: it is `cvttsd2si`'s ROUNDING sibling ($2D vs
$2C), and shipping only the truncating form is a trap, since truncation is not
the default behaviour anywhere else.

### Verified against gas, byte for byte

21 instructions covering every prefix family, both REX-extended registers
(`xmm9`, `xmm10`) and both GP widths of the conversions, assembled from
identical Intel syntax by `gcc -c` and by pxx:

**88 bytes, byte-identical.** (`objdump -d -Mintel` on the gas object vs a byte
search of the pxx binary; compared programmatically, not by eye.)

### Regression test

`test/test_asm_sse_scalar.pas`, wired into `make test-asm` beside the other asm
tests. It RUNS the arithmetic rather than pinning the bytes, because the bytes
are already pinned by the gas comparison above and pinning them twice would say
nothing new — whereas **a correct opcode with a wrong ModRM still encodes**, and
only execution catches that. Covers the store direction (`movsd r, xmm0` is
opcode $11, a different path from the load), `xmm9`/`xmm10` (REX.B/REX.R),
`cvtsi2sd` from both `Int64` and `Integer` (REX.W present vs absent — getting
that backwards reads the wrong half), and the truncate-vs-round pair on one
input.

### Phase 2+ unchanged

`cpuid`/`xgetbv`, packed SSE2, then VEX/AVX — as phased above. Two notes for
whoever takes them:

- **`movq` (xmm↔GP) is NOT in this phase.** `asmtext.inc` has it; `asmenc.inc`
  still does not. It is the natural bridge for moving a double between register
  files and should ride along with phase 2.
- **Add to BOTH encoders, or say why not.** The three-table split above is the
  real shape of this area, and the whole reason phase 1 was mis-scoped. A
  mnemonic added to `asmtext.inc` alone is invisible to Pascal inline asm, and
  vice versa.

## 2026-08-14 — PHASE 2 DONE: cpuid / xgetbv / rdtsc

Landed in **both** encoders (`asmenc.inc` and `asmtext.inc`), per the rule phase
1 ended on — a mnemonic goes in both or the reason is written down. All three
are zero-operand, so this is small; it matters because it is what makes runtime
ISA dispatch possible **before** any vector opcode exists. Without it the later
phases emit instructions no program can safely reach.

Encodings checked against gas: `cpuid` = `0F A2`, `xgetbv` = `0F 01 D0`,
`rdtsc` = `0F 31`.

Behaviour confirmed against `/proc/cpuinfo` on this box — leaf 0 gives
`GenuineIntel`, leaf 1 ecx bit 20 (SSE4.2) and bit 28 (AVX) both set, matching
the `sse4_2` and `avx` flags there.

### The test asserts only machine-INDEPENDENT facts

`test/test_asm_cpuid.pas`. The obvious test — compare the vendor string against
`GenuineIntel` — passes on the machine that wrote it and fails on every AMD one,
which is worse than not testing at all. So it pins what holds on any x86-64 CPU
that can run the binary:

- leaf 0 reports `maxLeaf >= 1`;
- the vendor string is 12 printable ASCII bytes (catches the
  register-never-loaded failure without caring which vendor);
- leaf 1 edx bit 26 (SSE2) is set — **x86-64 requires SSE2**, so this is
  universal rather than a property of this box;
- `rdtsc` returns two different values across a delay, tolerating a 32-bit
  low-half wrap rather than asserting an ordering that is false at the wrap.

**`xgetbv` is deliberately NOT executed** by the test. It faults `#UD` unless
`CR4.OSXSAVE` is set, which is itself discovered via leaf 1 ecx bit 27 — so
running it unconditionally would crash on older or restricted machines. Its
encoding is verified above; a program must gate on OSXSAVE first, and the test
should not model the wrong usage. That gating is exactly what `xgetbv` is *for*:
it distinguishes "the CPU has AVX" from "the OS actually saves the YMM state",
which is the check that decides whether an AVX kernel is safe to run.

### Remaining: phases 3 and 4

Packed SSE2 (`$66` over the existing scalar dispatch), then the VEX emitter and
AVX/FMA. Both encoders each time. `movq` (xmm↔GP) is still missing from
`asmenc.inc` and should ride along with phase 3 — it is the natural bridge for
moving a double between the register files.

## 2026-08-14 — PHASE 3 DONE: packed SSE2, plus the forms with a different operand SHAPE

### The operand model needed a third slot first

`AsmOpKind`/`AsmOpReg`/… were `array[0..1]` and the parse loop errored on a
third operand. So `cmppd xmm0, xmm1, 2` was not merely unencodable — it was
**unsayable**, rejected before any encoder saw it. Widened to `[0..2]` in
`defs.inc` (standalone arrays, not a record field, so no bootstrap hazard) and
the loop cap raised to 3. Doing it here rather than special-casing an immediate
inside the SSE arm keeps ONE operand model, which is the thing this ticket keeps
finding was split.

### Landed

**Plain `reg, rm` packed forms** — the same encoders as the scalar ones with the
`$66` prefix, so they are parameter values in the existing table rather than a
second dispatch: `addpd subpd mulpd divpd sqrtpd maxpd minpd andpd andnpd orpd
xorpd unpcklpd unpckhpd movapd movupd`.

**Forms whose operand SHAPE differs**, grouped separately because the table
above encodes "prefix + opcode" and these need an extra byte or a different
register file — folding them in would make the table lie about what it covers:

- `cmppd` / `cmpsd` — trailing imm8 predicate (0..7), validated rather than
  truncated;
- `shufpd` — imm8 lane selector;
- `movmskpd` — destination is a **GP** register and the source an xmm, i.e. the
  opposite reg/rm assignment from every other form here. That is precisely the
  mistake that encodes clean and reads the wrong register file;
- `movq` xmm↔GP/m64 — the bridge for getting a Double in and out of the vector
  file without a memory round trip. Both directions are `$66` REX.W forms and
  they are DIFFERENT opcodes ($6E in, $7E out), not one form with the operands
  reversed. This was flagged as missing at the end of phase 1 and is now in.

`AsmSseStoreOp` replaced the hardcoded `movsd`/`movss` store check: each move
has its OWN store opcode ($11, but $29 for `movapd`), and returning False for
everything else is what makes `addpd mem, xmm` an error instead of a silently
wrong encoding.

### Verified against gas — 22 instructions, 96 bytes, byte-identical

Covering every added form, both REX-extended operand roles (`mulpd xmm0,xmm9`
and `divpd xmm10,xmm1` put the extension on different halves), the trailing
imm8, the GP-destination form, and `movq` in both directions including
`movq xmm9, r11` which needs REX.R **and** REX.B. Compared programmatically.

Note gas normalises `movmskpd rcx, xmm11` to the `ecx` form — movmskpd always
writes 32 bits — and pxx agrees, because the encoder passes opSize=4 and so
emits no REX.W either.

### Test

`test/test_asm_sse_packed.pas`. Vectors are built from SCALAR variables through
`unpcklpd` rather than loaded from an array, deliberately: **`movapd` faults on a
misaligned address**, and a test that depended on a Pascal array happening to be
16-byte aligned would be a coin flip dressed as a regression test. Register-to-
register forms have no alignment question.

Both lanes are checked on every packed op — a packed instruction that only got
the low lane right would pass a low-lane-only test and be exactly as broken as
one that got neither. `maxpd`/`minpd` are set up so the answer comes from a
DIFFERENT source vector in each lane, or the check proves nothing. The
`cmppd` + `movmskpd` pair is tested together because that is how a real vector
kernel writes its escape test.

### NOT mirrored into asmtext.inc — and this is the "say why not"

Phase 1 ended on the rule *a mnemonic lands in BOTH encoders or the reason is
written down*. This is the reason.

`asmtext.inc` drives compiler-EMITTED asm. It has the scalar SSE because codegen
uses it; **nothing in the compiler emits packed SSE**, so mirroring 15 mnemonics
there would add an untested encoder path to the compiler's own emitter — a
liability, not an asset, and exactly the sort of unexercised code that is wrong
when someone finally reaches for it.

So: not mirrored, on purpose. If a codegen consumer appears (an `-O3` vectoriser
is the obvious one), mirror then, and the verified opcode table above is the
data to mirror — it is already byte-checked against gas.

### Remaining: phase 4

VEX prefix emitter, then AVX/AVX2 (`v*pd`, `vbroadcastsd`) and FMA. That is the
real chunk, and it carries the design decision this ticket named at the start:
2-byte vs 3-byte VEX selection, and a third SOURCE operand for the
non-destructive `v` forms. Note the operand model now has three slots, but the
third is used as an IMMEDIATE here; a `vaddpd dst, src1, src2` needs it to be a
REGISTER, so phase 4 should check that assumption rather than inherit it.
