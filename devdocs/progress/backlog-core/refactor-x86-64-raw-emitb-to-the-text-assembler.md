# x86-64 codegen: raw `EmitB($..)` bytes to the text assembler

- **Type:** refactor
- **Status:** in progress (2026-11-11)
- **Prio:** owner 2026-11-11 named it "the big elephant in the room"
- **Opened:** 2026-11-11

## Why

Owner 2026-11-11: large amounts of raw emitted machine code instead of the
in-house assembler; the goal is readable code, and improving the assembler for
special constructs is in scope. Measured that day (x86-64 hex lines with
`EmitB($`): ir_codegen.inc 2033, ir_codegen386.inc 1540, symtab.inc 742,
cparser.inc 148, thread_emit.inc 118, exception_emit.inc 112, emit.inc 69,
pasparser_lval.inc 62, coroutine_emit.inc 32. arm32 has ~1,221 raw
`EmitI32($E...)` words and aarch64 ~931. The ESP backends (Xtensa, RISC-V)
have no hex: they use typed encoders (`xtensa_l32i`, `rv32_addi`).

## How it is verified

Every batch is held to two oracles over a 472-file corpus (every 8th
test/*.pas, every test/*.py, compiler.pas), old compiler vs new:

1. **byte identity** of the output binary, or, where it differs,
2. **identical normalized disassembly** of the executable segment: objdump
   with addresses, raw bytes, branch targets and moved addresses blanked.

A difference that survives (2) is a real change and blocks the batch. The
expected kind of (1)-only difference is an encoding the assembler picks
shorter than the hand-written bytes forced (disp8 for a small `[rbp+%]`,
imm8 for a small immediate). Same instruction, fewer bytes.

The straight-line conversion is done by a script that rewrites a hex line only
when GNU `as`, assembling the line's own comment, produces exactly those bytes
(with a sentinel in place of the trailing `EmitI32(x)` hole). So a comment that
disagrees with its bytes is never trusted; that line stays raw and is listed.

## Assembler additions (asmtext.inc / x64enc.inc)

- scope labels: a dotless label lives from `AsmScopeBegin` to `AsmScopeEnd`,
  across calls and the Pascal between them; scopes nest; an undefined target
  or a duplicate definition is a compile error. `.name` labels stay per-call.
- `short` / `near` jump widths (forward rel8 with a range check).
- `jmp @code` / `jcc @code` / `call @code`: rel32 to a known code position.
- `gs:[..]` / `fs:[..]` segment overrides on any memory operand.
- absolute numeric `[%]` / `[0x10]` (disp32, no base).
- register holes `%r64` `%r32` `%r16` `%r8`, also as a memory base.
- `[base+index*scale+disp]`.
- `jmp reg` / `jmp [mem]`; three-operand `imul r, r, imm`; `cld` `std`
  `stosq` `movsq` `rep stosq` `rep movsq`.
- error messages name the offending line.
- two wasted-byte encoder bugs found by the disassembly oracle, both fixed:
  a byte ALU immediate with /4../7 (`cmp al, 0x30`) and a byte ALU
  `[rsi..rdi], imm` each carried a meaningless REX 40, because the /digit or
  the memory base went through the register rule that forces REX for
  spl/bpl/sil/dil.
- tests: test/test_asm_emit_x64.pas pins every addition (bytes checked
  against GNU as; where our encoder picks the r/m form over an al/eax short
  form, the test says so).

## Left

- jump/patch idioms (`p := CodeLen; EmitI32(0)` ... `Patch32`/`PatchRel8`):
  ~250 in ir_codegen.inc, ~100 in symtab.inc. Want scope labels; the hazard is
  an `Exit` between AsmScopeBegin and AsmScopeEnd.
- computed opcode bytes (`EmitB($E0 + reg)`): register holes.
- comments that are not assembly, or disagree with their bytes.
- i386 (EmitAsm386 needs the same label/@code additions), arm32, aarch64.
