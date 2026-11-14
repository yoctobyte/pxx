---
track: C
tags: [C, inline-asm, gibux]
prio: 30
type: feature
summary: "C inline asm accepts lfence, mfence and sfence (0F AE E8/F0/F8) on x86-64 and i386; before, the template was refused with 'unsupported instruction: mfence'. Asked for by the Gibux session. The x86-64 disassembler decodes them too."
status: done
owner: unassigned
found: 2026-11-14
---

# C inline asm: lfence / mfence / sfence

Gibux hit `C: inline asm template has an unsupported instruction: mfence`.
The gas front end (gasfront.inc) already had all three. The AT&T inline-asm
path did not.

Added, keeping the encoders in step:

- `compiler/asmatt.inc` AttKnows386: the three mnemonics;
- `compiler/asmenc.inc` (x86-64 byte encoder);
- `compiler/asmtext.inc` and `compiler/asmtext_386.inc` (text assemblers);
- `compiler/asmdisasm_x64.inc`: decodes 0F AE E8/F0/F8, which used to print
  as `db`.

Tests: `test/c_inline_asm_fences.c`, rows c_asm_fences and c_asm_fences_i386.
All three byte sequences were checked in both binaries.
