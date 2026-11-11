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

## Progress

- 2026-11-11 batch 1 (54a6cced1f): ~1,300 straight-line lines; exception
  runtime and clone stub whole. Remaining EmitB($ lines: ir_codegen 1317,
  symtab 494, cparser 126, thread_emit 63, exception_emit 33 (i386), emit 66,
  pasparser_lval 33, coroutine_emit 15.
- batch 2: 161 forward-jump placeholders in 29 routines become scope labels
  (named from the jump's own comment, `.missplain` -> `missplain`; jumps that
  land on one spot share one label; the placeholder variables are gone).
  Only routines with no `Exit` (an Exit would skip AsmScopeEnd) and only
  variables with exactly one jump and one patch.
- batch 3: ~250 lines with holes converted in place (ir_codegen 168, symtab
  61, cparser 9, emit 5, pasparser_lval 9), including the hot emit.inc
  helpers (MovRaxImm & co). Remaining EmitB($ lines: ir_codegen 866, symtab
  367, cparser 91, thread_emit 63, exception_emit 33, emit 62,
  pasparser_lval 21, coroutine_emit 15. This batch found three encoder
  defects (done/bug-x86-64-encoder-spurious-rex-on-byte-memory-ops-and-
  missing-accumulator-forms.md); the self-hosted compiler's code is 77 KB
  smaller for it. It also added a missing feature: SSE scalar to and from
  [@glob]/[@data]/[num].

## Compile-time cost, and the whole-call memo

Converting hot codegen to EmitAsmX64 costs compile time. Every hole line went
through label/jump classification and the full lexer on each emission. The
fixed-line memo skips lines with holes, and nearly every converted line has
one. Callgrind on lib_charset.pas, compiler instruction totals:

| compiler | instructions |
|---|---|
| batch 2 | 2.494 G |
| batch 3 | 2.707 G (+8.5%) |
| batch 3 + whole-call memo | 2.554 G (+2.4%) |

The whole-call memo (asmtext.inc, above EmitAsmX64) keys on the line text plus
the exact hole values. A lookup reads the literal in place and allocates
nothing. Entries are admitted by observation: one plain instruction, no fixup,
syscall or scope-label counter moved, and no `@`. On lib_charset the hit rate
is about 97%. Check it with `PXXDBG='a.asmmemo:*'`. Across the corpus, in all
five configurations, the memo build was byte-identical to the build without
it (1,090 SAME, 0 DIFF).

The remaining +2.4% is the open-array constructor: each `[...]` argument is
heap-built and released per call
(backlog-core/perf-an-open-array-constructor-argument-is-heap-built-per-call.md).
Fixing that removes it and also speeds up user programs that call Format.

**Before converting another hot path, profile it.** The compiler binary has no
symbols. Symbolize callgrind addresses with the `.map` file written beside the
compiler binary.

## The hazard this work has, and the guard for it

A hand-counted literal jump (`EmitB($74); EmitB(5)` = `je +5`) is correct only
while what it spans keeps its size. Converting the span to EmitAsmX64 lets the
assembler pick another encoding -- and it does pick shorter ones. The gate's
rel8 lint (tools/rel8_literal_span_check.py) refuses such a span; it caught 12
in batch 1, all now labels. The disassembly oracle used to blank branch
targets, which is exactly where this bug would show; it now compares each
target as an INSTRUCTION-COUNT offset, which encoding sizes cannot move, and
flags a target that is not an instruction start (mutation-tested: one rel8
byte +1 is reported).

## Left

- jump/patch idioms (`p := CodeLen; EmitI32(0)` ... `Patch32`/`PatchRel8`):
  ~250 in ir_codegen.inc, ~100 in symtab.inc. Want scope labels; the hazard is
  an `Exit` between AsmScopeBegin and AsmScopeEnd.
- computed opcode bytes (`EmitB($E0 + reg)`): register holes.
- comments that are not assembly, or disagree with their bytes.
- i386 (EmitAsm386 needs the same label/@code additions), arm32, aarch64.
