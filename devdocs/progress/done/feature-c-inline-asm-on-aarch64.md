---
track: C
tags: [C, inline-asm, aarch64, dropbear]
prio: 40
type: feature
blocked-by: []
summary: "GNU C inline asm now works on aarch64 for register/immediate data processing. That covers shifts, logical ops with bitmask immediates, add/sub/cmp with extended registers, bitfield extracts, rbit/clz, cset/csetm/csel and friends, and mov/neg/mvn/mul. Constraints \"r\" (\"g\"/\"rm\" as a register) and \"i\" work, with =, +, & and tied inputs. Operands are pinned to x10..x15 and the template is encoded at parse time; the aarch64 IR_ASM arm loads inputs and stores outputs through the backend's own helpers. All 90 test encodings match llvm-mc byte for byte. dropbear's sntrup761.c compiles for aarch64."
status: done
owner: unassigned
---

# GNU C inline asm on aarch64

Found building dropbear for aarch64 ([[feature-c-dropbear-builds-with-pxx]],
acceptance 5). sntrup761.c has `#elif defined(__aarch64__)` arms with 78
`__asm__` statements over 15 mnemonics (asr lsl lsr and orr tst cmp cset
csetm csel sxth ubfx sbfx rbit clz). pxx refused them: "inline asm with a
non-empty template is only supported on x86-64 and i386".

## Design (compiler/casm_a64.inc)

The x86 path wraps the encoded bytes in frame-slot moves at parse time.
That does not carry over to aarch64, whose locals can live in registers and
whose frame addressing belongs to codegen. So the work is split at the seam
the operands cross:

- **Parse time** (`CAsmBuildBlockA64`, cparser.inc). Each register operand
  gets its own register from x10..x15 (a tied input shares its output's), so
  `&` holds by construction. Every `%N`, `%wN`, `%xN` and `%[name]` is
  replaced by its register name; without a modifier, an 8-byte operand
  prints x and anything narrower w, as gcc prints by mode. An `"i"` operand
  is replaced by its value. The text is then encoded into AArch64 words in
  AsmBytes. Each operand gets a temporary of its C type, and the block
  records which temporary feeds or drains which register
  (`CAsmA64Bind*`, defs.inc). The AST is `tmp = expr` per input, then
  AN_ASM with `ASTIVal = block + 1`, then `expr = tmp` per output.
- **Codegen** (the IR_ASM arm of ir_codegen_aarch64.inc, when IRIVal > 0).
  Each input goes through `EmitLoadVarA64Dest(sym, reg)`, the words are
  copied, and each output goes through `mov x0, xR` + `EmitStoreVarA64`.
  Those helpers touch only x0, x1, x9 and d0, which is why the pool is
  x10..x15. A body with IR_ASM already gets no register residency.
  IRIVal = 0 is a Pascal `asm` block, which keeps its text-replay path.

Clobbers of x0..x17 are accepted. A callee-saved register (x18 and up) is
refused, because nothing saves it around the block. Memory operands,
labels, branches and other constraints are refused by name.

## Tests

- `tools/check_casm_a64_encodings.sh` (row casma64enc). It puts every line
  of `test/casm_a64_encodings.s` (90 instructions, every form dropbear uses
  plus the rest of the set) into one operand-less `__asm__`, compiles it
  for aarch64, and requires that run of words to equal llvm-mc's encoding,
  byte for byte. It skips when no llvm-mc is installed.
- `test/casm_a64_operands.c` (rows casma64op_a64, casma64op_x64): dropbear's
  helper templates verbatim. They cover `=r`, `+r`, `+&r`, `=&r`, tied
  inputs, 16/32/64-bit types, a three-output block, a named operand and an
  `"i"`. Each is checked against its portable C over an input sweep. The
  aarch64 build runs the asm under qemu, the x86-64 build runs the portable
  arms, and both print gcc's numbers.

## Found on the way

- `ir_codegen_aarch64.inc` briefly had two `IR_ASM:` arms. pxx compiled it
  and the first silently won; only the FPC seed canary refused it. Filed as
  [[bug-p-a-duplicate-case-label-compiles-and-the-first-arm-wins]].
