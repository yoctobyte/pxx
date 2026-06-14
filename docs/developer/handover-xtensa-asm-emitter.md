# Handover — Xtensa text-assembler (`EmitAsmXtensa`) for ESP32

Paste this into a fresh session to start the work.

---

You're adding a **Xtensa text-assembler** to the Pascal26 (PXX) compiler, the
ESP32-primary sibling of the existing x86-64 `EmitAsmX64`. Goal: write Xtensa
codegen as readable assembly text instead of hand calls to the `xtensa_*`
encoders, to make ESP32 work cleaner. This is **new code on top of existing
encoders**, landed incrementally — not a rewrite.

**Read first (in repo):**
- `docs/progress/backlog/feature-xtensa-asm-emitter.md` — the ticket (scope,
  acceptance, deferrals). Authoritative.
- `compiler/asmtext.inc` — the x86-64 precedent `EmitAsmX64`. Copy its shape:
  interleaved `array of const` of instruction strings + `%`-hole ints, one
  instruction per string, encoded via the typed encoder layer. Note its helpers:
  `AsmTextCharAt` (range-checked char read — REQUIRED, see landmine below),
  `AsmTextSlice` (no `Copy` in the dialect), `AsmTextParseInt`, and the
  hole-binding + label/jump loop in `EmitAsmX64`.
- `compiler/xtensaenc.inc` — the typed `xtensa_*` encoders you build on
  (`xtensa_add/addi/l32i/s32i/movi/beq/bne/blt/bge/j/ret/nop/…`). This is your
  lower layer; the text-assembler just parses mnemonics+operands and calls these.
- `compiler/ir_codegen_xtensa.inc` — the consumer; pick one block to convert.
- `docs/progress/backlog/feature-asm-text-emitter.md` — x86-64 ticket, for the
  marker/label design rationale.

**Hard-won facts to honour (don't rediscover):**
- Xtensa: L32R offsets are one-extended → ALWAYS negative (literal sits before a
  4-aligned `l32r`); J imm18 at insn bits [23:6] (not `<<4`); RET = LE `80 00 00`;
  CALL0 target = `align4(PC)+4+imm*4` (proc entries NOP-padded to 4). Memory:
  `project_esp32_stage1`. **Defer all L32R literal-pool sugar** — it's the
  gnarliest piece and not needed for a first useful slice.
- **PXX self-host landmines** (this code runs in the compiler, compiled by both
  FPC and PXX): (1) PXX does NOT short-circuit `and`/`or`, and indexing an EMPTY
  `AnsiString` derefs nil → segfault; so `(Length(s)>0) and (s[i]=..)` crashes —
  route conditional char reads through `AsmTextCharAt`. (2) No `Copy` — use
  `AsmTextSlice`. (3) Never reassign a `var AnsiString` param — return the value.
  (4) Local `array of AnsiString` is a landmine — keep scratch/label tables
  module-global (as `EmitAsmX64` does). Memory: `project_pxx_and_not_shortcircuit`.

**Operand model (simpler than x86 — no ModRM/brackets):** flat regs `a0..a15`
(`sp`=`a1`); `mnem dst, src, imm` comma-separated; loads/stores are
`l32i at, as, off` (base reg + immediate, not bracketed); `%` = next int hole;
`.name:` labels with `j`/`bXX` computing target-relative offsets, back+forward.

**First slice (smallest useful):**
1. Add `compiler/asmtext_xtensa.inc` (or extend `asmtext.inc`; prefer factoring
   the target-agnostic helpers so both share them). Include it after
   `xtensaenc.inc` and before the consumer in `compiler/compiler.pas`.
2. `EmitAsmXtensa(const items: array of const)` covering the instructions
   `ir_codegen_xtensa.inc` already uses (see ticket list), plus labels + `j` and
   `beq/bne/blt/bge` relative-offset resolution.
3. Convert ONE branch/label-bearing `ir_codegen_xtensa.inc` block to it.
4. Verify with the Xtensa run path (`tools/run_target.sh xtensa …`, the
   `make test-*` xtensa slices, QEMU as applicable) and a focused encoding test
   against llvm-mc (the oracle used before). Keep `make bootstrap` byte-identical.

**Build/test loop:** `make bootstrap` (FPC→PXX→PXX, must `cmp` clean — this is
your self-host correctness gate). `make test` for the native suite. Xtensa:
check the Makefile for the xtensa/esp targets and `tools/run_target.sh`.

**Workflow:** work on `master`, commit each logical unit (no batching), don't
push without explicit OK. Caveman comms mode is on for this user.

Start by reading the ticket + `asmtext.inc` + `xtensaenc.inc`, then propose the
first concrete instruction subset and the one block you'll convert.
