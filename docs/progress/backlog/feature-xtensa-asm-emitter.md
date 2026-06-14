# Xtensa text-assembler (`EmitAsmXtensa`) for ESP32

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Depends-on:** feature-array-of-const (DONE), feature-asm-text-emitter (x86-64 precedent)
- **Opened:** 2026-06-14

## Motivation

ESP32 codegen (`ir_codegen_xtensa.inc`) emits Xtensa through hand calls to the
`xtensa_*` encoders, and the ISA's sharp edges — L32R's always-negative literal
offsets, CALL0 `align4(PC)+4`, J's imm18 at bits [23:6], RET = `80 00 00` — make
that error-prone and a session-eater to debug (see [[project_esp32_stage1]]).

Same idea as the x86-64 emitter ([[project_array_of_const_and_asm_emitter]],
`feature-asm-text-emitter`): write emit blocks as **assembly text** parsed and
encoded by a per-target text-assembler, with runtime `%` holes bound inline.
Readable, fewer bugs, and it doubles as the backend for eventual Xtensa inline
`asm … end`. **Xtensa is the primary target** here — it makes ESP32 work cleaner.
This is mostly **new code on top of `xtensaenc.inc`**, not a rewrite; ESP32
progress is chaotic, so land it incrementally.

## Precedent to copy

`compiler/asmtext.inc` (`EmitAsmX64`) is the template: interleaved
`array of const` of instruction strings + `%`-hole ints, one instruction per
string, encoded through the typed `x64_*` layer. `EmitAsmXtensa` is the same
front-end over the typed `xtensa_*` layer (`compiler/xtensaenc.inc`). Reuse the
shared helpers' shape (`AsmTextCharAt`, `AsmTextSlice`, `AsmTextParseInt`,
hole-binding loop) — ideally factor the target-agnostic bits so both emitters
share them rather than copy.

## Operand model (simpler than x86 — no ModRM/brackets)

Xtensa is mostly 24-bit (some 16-bit narrow) with a flat register file `a0..a15`
(`sp` = `a1`). Instructions are `mnem dst, src, …` comma-separated; loads/stores
take a base register + immediate offset, **not** bracketed memory:

```
l32i  a3, a2, 8        ; a3 := [a2 + 8]
addi  a4, a4, %        ; immediate hole
beq   a3, a5, .loop    ; branch to label
j     .done
```

- registers `a0..a15` + `sp` alias.
- `%` value hole → next `vtInteger` element (immediate / offset / branch is
  size/range-checked per instruction).
- `.name:` label; `j .name`, `bXX as, at, .name` pick the encoding and compute
  the (target-specific) relative offset, back and forward.

## Scope (incremental)

1. **Cover the instructions `ir_codegen_xtensa.inc` already uses first**:
   `add sub and or xor mull mov movi addi`, `l32i l16ui l16si l8ui s32i s16i
   s8i`, `nop ret`, branches `beq bne blt bge` + `j`. Grow on demand.
2. Labels + branch/J relative-offset resolution (back + forward), honouring the
   J imm18-at-bits[23:6] and branch range/encoding rules.
3. Emit through the existing `xtensa_*` encoders + byte sink — no new relocation
   machinery.
4. **Convert one real `ir_codegen_xtensa.inc` block** to `EmitAsmXtensa` (a
   fixed/branchy one), leave heavily-dynamic blocks on the typed encoders. Mix
   freely, like the x86 emitter does.
5. **Defer** (call out clearly): L32R literal-pool sugar (the jump-over-island +
   always-negative `l32r rd, $FFFF` scheme — the gnarliest piece), 16-bit narrow
   encodings, windowed-ABI `entry`/`call8` sugar, `--target=esp32` IDF specifics.

## Landmines (PXX self-host — the emitter runs in the compiler)

- **No short-circuit `and`/`or`** and EMPTY-AnsiString index = nil deref →
  segfault. Route every conditional char read through a range-checked accessor
  (`AsmTextCharAt`). See [[project_pxx_and_not_shortcircuit]] /
  feature-short-circuit-eval.
- **No `Copy`** — use the slice helper. **Never reassign a `var AnsiString`
  param** (frozen-inline overflow) — return the value.
- Local `array of AnsiString` is a self-host landmine — keep scratch tables
  module-global (as `EmitAsmX64` does for its label tables).
- Xtensa encoding facts that already cost a session: L32R one-extended (negative)
  offsets; J imm18 at [23:6] (not `<<4`); RET LE `80 00 00`; CALL0 target
  `align4(PC)+4+imm*4` (proc entries NOP-padded to 4). All in
  [[project_esp32_stage1]] and `xtensaenc.inc`.

## Acceptance

- `EmitAsmXtensa(const items: array of const)` with the register/`%`/label rules,
  one instruction per string.
- At least one `ir_codegen_xtensa.inc` block converted (a branch/label-bearing
  one), output still correct under the Xtensa run path
  (`make test-* ` / `tools/run_target.sh xtensa …` / QEMU as applicable).
- A focused `test/test_asm_emit_xtensa.*`-style check exercising imm/offset/
  branch/label encodings against known-good bytes (llvm-mc is the encoding oracle
  used previously).
- Bootstrap byte-identical; the Xtensa target fixedpoint (where one exists) stays
  consistent.

## Log

- 2026-06-14 — opened. Mirrors the x86-64 `EmitAsmX64` work; primary target
  Xtensa to clean up ESP32 codegen. New code over `xtensaenc.inc`; literal-pool
  sugar explicitly deferred.
