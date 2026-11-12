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
- `movd xmm, [mem]` / `movd [mem], xmm`; `xadd` and `cmpxchg` (reg or mem
  destination, 32/64 bit, usually behind `lock`); absolute `[@glob]`
  sources for movzx/movsx/movsxd; `stmxcsr` / `ldmxcsr [mem]` (batch 7).
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

- batch 4 (raw-asm batches 22+23, 2026-11-11):
  - 188 more commented lines converted in place. The converter now accepts
    `= x` / `; x` remarks, double spaces inside operands, an inferred
    `qword`/`dword` size, and constant EmitI64 tails.
  - All ~60 computed-opcode lines (`EmitB($C0 or ((r - 8) shl 3))`) now use
    register holes, including the new `%xmm` hole. The code passes the full
    register number and the assembler derives REX.R/REX.B, so the hand
    `(r - 8)` arithmetic is gone.
  - EmitAluRaxRight and EmitW2InPlace pick the instruction TEXT by operation
    instead of an opcode byte.
  - New assembler forms: cdqe, bt/bts/btr/btc reg,imm8, movd r32<->xmm,
    movaps/movapd.
  - New regression test: test/test_x64_register_hole_paths.pas (test-threads,
    -O0 and -O3). It was mutation-checked: movsx->movzx in the narrow
    re-extend turns -68 into 188.

- batch 5 (2026-11-11): 264 UNCOMMENTED lines (ir_codegen 169, symtab 95).
  Here the comment cannot be the oracle, so the candidate text comes from
  objdump on the run's bytes, with sentinel values in the hole positions. A
  candidate is accepted only when GNU as reproduces those bytes and our own
  assembler, fed the same sentinels, also reproduces them. The second check
  is a generated harness over all 136 distinct lines; the only differences
  are the three `[@glob]` forms, where the mock writes the fixup as zeros.
  A one-byte run can decode as an instruction and still be a fragment.
  `2: EmitB($95); { rdx }` is a ModRM byte in a case arm, and objdump reads
  it as `xchg ebp, eax`. So every objdump-sourced line was reviewed in
  context. Three were fragments and stay raw: ir_codegen ~1085 (the REX
  prefix comes from the line above) and the two ModRM case arms ~3327 and
  ~3448. The rel8 lint then caught three hand-counted short jumps in the
  frozen-string concat (`EmitB($74); EmitB(15)`, `EmitB($EB);
  EmitB(Byte(-20))`, `EmitB($7E); EmitB(7)`) that now spanned EmitAsmX64.
  That block is now one labelled sequence per copy loop.
- batch 6 (2026-11-11):
  - 58 reloc-shaped lines (`48 B8+r EmitDataRef` -> `mov r64, @data`;
    `48 8B/89 modrm 25 EmitGlobRef` -> `mov r64, [@glob]` /
    `mov [@glob], r64`), in ir_codegen, symtab, pasparser_lval and emit.
    Only REX.W runs, which are x86-64 by construction.
  - 58 forward-jump placeholders in routines that DO have an `Exit` now use
    scope labels, each with a TIGHT scope around its own jump and landing
    site. A region qualifies only if it has no Exit/Break/Continue/raise,
    balanced begin/end (and repeat/until), whole-line statements at both
    ends that are not under an if/else without begin, and no other dotless
    label text. Overlapping regions merge into one scope.
  - The first version paired a jump with the FIRST of its patches.
    EmitObjRefFastPath patches `pDone` in both arms of an if/else, so the
    release arm lost its landing label. That would have been an
    "undefined scope label" error, though only when that path compiled.
    It is fixed (each arm defines `done:`), and the converter now refuses a
    placeholder with a second patch. The other leftover patches of
    converted names were checked one by one; all belong to jumps that are
    still raw.
  - Dead placeholder variables removed.
  Remaining EmitB($ lines: ir_codegen 389, symtab 182.
- batch 7 (2026-11-11):
  - EmitPromoInline, EmitVarGetItemInline, EmitListAtInline: 18 jcc rel8
    placeholders collected in a `slow[]` patch list become `jcc short slow`,
    one asm scope per routine, `slow:` after the `jmp done`. (Each routine's
    `jmp done` rel8 is patched by its caller, so it stays raw.)
  - IR_LOAD_MEM / IR_STORE_MEM: 12 sites built the ModRM by hand
    (EmitRaxMemModRM, now removed) and are `[rax+%]` with the folded field
    offset; the assembler picks the same none/disp8/disp32 width.
  - EmitSetccFloat's four setcc/and/or triples; three `cqo; idiv rcx`.
  - `rep movsb` / `rep stosb`: ir_codegen 15, symtab 6, pasparser_lval 4.
  - imm64 moves (`48 B8+r EmitI64`) as `movabs r64, %`: ir_codegen 3,
    symtab 16, emit 3. `movabs` because plain `mov` would shrink a small
    hole value to imm32.
  - four `lock xadd` / `lock cmpxchg` (ATOMIC_ADD/CAS, 32 and 64 bit).
  - symtab: 20 `[@glob]` loads, stores and compares (movsx/movzx/movsxd
    included).
  - MXCSR: ir_codegen's rounding-mode get/set (3 plus the split
    `and ecx, ~0x1F80`) and cparser's x86-64 fenv stubs (3). The stubs are
    not in the compiler's own code, so c_fesetround_rounds_or_refuses and
    lib_rounding_contract were compared A/B: byte-identical, both pass.
  Every new encoder form was checked against GNU as at every displacement
  width. The fixedpoint converged in one round after each step, which means
  the old and the new emitter produced the same compiler. Sampled A/B
  (every 8th Pascal test plus all test_nilpy_*.py, default -O2): 356 SAME,
  0 DIFF.
  Remaining EmitB($ lines: ir_codegen 325, symtab 140, cparser 88, emit 58,
  pasparser_lval 13. Most of cparser's and much of symtab's are i386.

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

**Resolved: the remaining cost was the exit sweep.** Each `[...]` site owns a
hidden dyn-array temp, and every exit released all of them, nil or not.
IREmitNode made 18.8 M release calls on one compile. A nil slot now skips the
release (done/perf-x86-64-scope-exit-releases-every-nil-dyn-array-temp.md).
After that fix the compiler with batches 22+23 runs 2.294 G instructions on
lib_charset, 8% BELOW the pre-conversion compiler (2.494 G).

**Batch 23 follow-up: the memo now keys on the literal's address.** The
probe cost ~1000 instructions per call (58,867 calls on lib_charset), mostly
two per-character loops: hashing the line text and comparing it on a hit. An
immortal string literal (`PInt64(p-16)^ >= $20000000`, the same test
pylib's PyAttrLkStaticH uses) is now keyed by its address; anything else
keeps the text key. EmitAsmX64 carries the probe's pointer to the store
itself, because the stored `line` may be a copy. lib_charset: 2.417 G ->
2.376 G; the compiler it builds is byte-identical.

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
- i386: the rest, below. arm32, aarch64.

## i386 (2026-11-12)

**Labels first.** EmitAsm386 now has the x86-64 jump forms:
- scope labels, sharing AsmScopeBegin/AsmScopeEnd. The scope code moved out of
  asmtext.inc into compiler/asmscope.inc so both assemblers and both test
  harnesses use one copy.
- `short` / `near`, `jmp|jcc|call @code`, and constant `jcc +N`.
- The inline-asm replay keeps every label local to its asm block, even
  inside an open scope (Asm386ProcessLineEx's allowScope).

**The i386 test now runs the shipped code.** test_asm_emit_386 carried its
own mock AsmTextOperand and EncModRMMem, and they had drifted from the real
ones. It now includes asmregs/x64enc/asmtext like the x64 harness. That
exposed a real bug: an indexed operand leaked its index register into the
next memory operand
(done/bug-an-indexed-i386-asm-operand-leaks-its-index-into-the-next-memory-operand.md).

**Assembler additions** (each pinned in test_asm_emit_386 with GNU as --32
bytes):
- `push imm` and `push dword [mem]`
- x87 fld/fst/fstp/fild/fistp/fisttp dword|qword, fldcw/fnstcw, frndint
- cld/std, stmxcsr/ldmxcsr
- `imul r, [mem]`, xchg (90+r with eax), rol/ror/rcl/rcr
- `movd xmm<->r32`, shld/shrd with cl or imm8, `mov r32, sreg` / `mov sreg, r32`
- accumulator short forms (04/05+8*op, A8/A9), as GNU as picks them
- 32-bit immediates read modulo 2^32 (`and eax, 0xfffffff0` takes imm8)

**Batch i1 (ir_codegen386.inc, 915 lines) and batch i2 (172 lines in the i386
regions of thread/exception/coroutine_emit, cparser, symtab, emit).** Method:
- objdump decodes the line's bytes (a sentinel in the EmitI32 hole).
- The comment's first word must name the first decoded instruction.
- GNU as must reassemble the proposed text to the same bytes.
- A harness built on the shipped parser and encoder must produce those bytes
  for SEVEN hole values (0, +-8, +-200, 0x12345, the sentinel). This rejects
  every line whose raw form forced a wide encoding (`[ebp+disp32]`, `81 /op
  imm32`), so the output stays byte-identical.
- Mixed files convert only inside `if TargetArch = TARGET_I386` bodies,
  `TARGET_I386:` case arms and *386 routines. Bytes alone cannot tell them
  apart: `50` is push eax and push rax. Brace comments nest in this codebase,
  which the region scanner had to learn.
- Consecutive lines merge into one EmitAsm386([...]). A line under a bare
  then/else/do is never merged.

12 hand-counted short jumps that now spanned EmitAsm386 calls became local
labels, 11 forward ones (rel8 lint) and the thread stub's backward
`jnz .z`, which the lint does not check.

Verified:
- fixedpoint after every step.
- A/B against the pre-i386 compiler over 795 --target=i386 sources (every
  Makefile i386 row, every 6th Pascal test, compiler.pas): 688 SAME, 0 DIFF,
  107 fail to compile with both compilers.
- A 159-file x86-64 sample: 137 SAME, 0 DIFF.

Remaining raw `EmitB($` lines: ir_codegen386 598, symtab 116, emit 45,
cparser 36, thread_emit 15, exception_emit 10. Mostly:
- forced-wide hole forms. Converting them shrinks code; that is a decision,
  not a cleanup.
- patch-list jumps (`p := CodeLen; EmitI32(0)` ... Patch32), which want
  scope labels.
- computed ModRM bytes, which want register holes.
- uncommented lines.
