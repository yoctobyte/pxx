---
track: C
tags: [C, inline-asm, xtensa, esp32, gibux]
prio: 30
type: feature
blocked-by: []
summary: "GNU C inline asm now compiles on xtensa (ESP32/S2/S3). Operands are pinned to a3..a6/a10/a11 (\"a\"/\"r\", \"g\"/\"rm\" as a register, immediates \"i\"/\"n\", = + & ties and %[name]). The template is kept as text lines and replayed at codegen through the same xtensa text assembler a Pascal asm block uses, now with rsr/wsr/xsr by name or dotted, rur/wur threadptr, rsil, waiti, the sync barriers, s32c1i, l32ai and s32ri. An instruction the assembler lacks poisons a static or header routine instead of stopping the compile, so an unused static inline costs nothing (rump-pxx g20 on xtensa)."
status: done
owner: unassigned
---

# GNU C inline asm on xtensa

Asked for by the Gibux seat, which is porting its kernel to the ESP32-S3 with
no FreeRTOS. Its arch headers need rsr/wsr/xsr (PS, INTENABLE, CCOUNT,
CCOMPARE, VECBASE), rsil, waiti, memw/isync/rsync and s32c1i with SCOMPARE1.
pxx refused every non-empty template on xtensa; 51 of 60 kernel files stopped
there, 13 of them only in unused static inlines.

## Design

aarch64's split (casm_a64.inc), with one change: the template is not encoded
at parse time. `CAsmBuildBlockXtensa` (cparser.inc) pins each operand, replaces
`%N` / `%[name]` with a register name or a value, and stores the lines in the
InlineAsmLine pool a Pascal asm block on this target already fills. The
xtensa IR_ASM arm loads each input through a2 into its register, replays the
lines through `AsmXtensaProcessLine`, and stores each output back through a2.
So one text assembler serves both languages.

- Pool: a3..a6, a10, a11. These are caller-saved under both ABIs and not used
  by the load/store helpers (a2, a8, a9) or the frame (a7 biased base,
  a15 fp).
- Clobbers: a2..a6 and a8..a11 are allowed, and so are a12..a14 when windowed.
  a0, a1, a7 and a15 are refused, as is a12+ under call0. `sar` is ignored.
- Operands wider than 4 bytes, or floating point, are refused by name.

New encodings in xtensaenc.inc (xsr, rsil, waiti, the sync family, rur/wur,
l32ai/s32ri) and the special-register and user-register name tables in
asmtext_xtensa.inc. Every number and byte pattern was read back from
xtensa-esp32s3-elf-as, not taken from the manual.

## Unused static inlines

pxx lowers a static inline even when nothing calls it. `AsmXtensaLineKnown` is
asked at parse time; an unknown line in a static routine or an imported header
sets `ProcAsmPoison`, so only a call refuses. Anywhere else the compile stops at
parse time, naming the line.

## Tests

- `test/c_xtensa_inline_asm.c` under qemu-xtensa (call0, the hosted ABI):
  ties, names, immediates, early-clobber, a compare-and-swap that hits and
  one that misses, and acquire/release forms.
- `tools/check_casm_xtensa.sh` compiles `test/c_xtensa_inline_asm_sys.c` with
  `--target=esp32s3 --freestanding` (windowed) and compares Espressif
  objdump's reading of every privileged form. It also checks the poison
  behaviour.

Windowed code is verified only by disassembly; hosted xtensa has no windowed
entry stub.
