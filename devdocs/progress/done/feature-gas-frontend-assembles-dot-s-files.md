---
track: B
tags: [asm, x86-64, elf, gibux]
prio: 50
type: feature
blocked-by: []
summary: "pxx assembles GNU as sources: `pascal26 --emit-obj foo.S foo.o` (.S through pxx's C preprocessor with __ASSEMBLER__, .s without) writes an ET_REL object. Gibux's boot.S and entry.S assemble with it, so the whole kernel now builds with pxx alone, and it boots hello and test-sh. Instructions go through the inline-asm AT&T reader and the one x86-64 encoder; a symbolic operand is encoded as a unique placeholder and its bytes located, which is where the relocation goes. .code32 reuses the 64-bit encoder, which refuses REX and rip. Gibux item 5."
status: done
owner: unassigned
---

# The GNU as frontend assembles .S/.s files

compiler/gasfront.inc. A `.S` or `.s` input goes straight to an object.
`.S` passes through pxx's C preprocessor first, with `__ASSEMBLER__`
defined (CPAsmSource in cpreproc.inc).

## What it reads

- **Sections:** `.text`, `.data`, `.bss`, `.section name, "flags", @type`
  (flags a/w/x; types progbits/nobits/note/init_array/fini_array), and
  `.previous`.
- **Symbols:** `.globl`/`.global`, `.weak`, `.local`, `.type`, plus `.set`,
  `.equ` and `name = expr`. `.size`, `.hidden`, `.file` and `.cfi_*` are
  accepted and ignored.
- **Data:** `.byte`, `.word`/`.short`, `.long`/`.int`, `.quad`, the
  `.Nbyte` forms, `.ascii`/`.asciz`/`.string` with escapes, `.skip`/`.space`,
  `.zero`, `.fill`, `.org`, `.balign`/`.p2align`/`.align` (code is padded
  with nop).
- **Blocks:** `.macro` with `\arg`, defaults, `\()` and `\@`; `.rept`.
- **Labels:** named labels and numeric locals (`1:` with `1b`/`1f`).
- **Expressions:** gas's precedence, under which `|&^!` bind tighter than
  `+-`. A value is constant + symbol − symbol, and a same-section
  difference folds to a constant.
- **Modes:** `.code32` and `.code64`.

## How instructions are encoded

- **Ordinary instructions** go through asmatt.inc's AttEncodeOne and
  AsmDispatch, the inline-asm path. asmatt gained a GAS mode (AttGasMode):
  bare absolute addresses, `disp(,%idx,s)`, and 32-bit address registers
  under `.code32`.
- **Absolute operands with no base** now use asmcore's SIB no-base form.
  It decodes the same in 32-bit and 64-bit mode.
- **Symbolic operands** are rewritten to a unique 32-bit placeholder before
  encoding. The placeholder is then found in the bytes, exactly once, and
  that offset gets the relocation: R_X86_64_32 in 32-bit code,
  R_X86_64_32S in 64-bit code. A placeholder that cannot be found, such as
  a symbol in a 16-bit immediate, is an error.
- **`sym(%rip)`** is encoded as an absolute placeholder, then rewritten:
  the SIB byte is deleted and rm is set to 101. So every instruction that
  takes memory also takes rip, with an R_X86_64_PC32.
- **Encoded here directly:** branches, `movabs`, `ljmp`/`lcall`, `iretq`,
  `ret $n`, and a table of zero-operand system instructions.
  - Branches always use rel32 (no relaxation). Targets in the same section
    resolve here; anything else becomes R_X86_64_PLT32. `loop` and `jecxz`
    are rel8 and local only.
- **`.code32`** reuses the 64-bit encoding wherever no REX is needed; a REX
  byte or rip addressing is refused. `mov` to or from a control register
  takes the 64-bit register name (the bytes are the same).

## Object

A small ET_REL writer:
- user sections;
- a `.rela` section for each section that has relocations;
- a symtab with section symbols, named locals, then globals and referenced
  undefined symbols.

Local targets are relocated through their section symbol.

## Verified

- tools/check_gas_frontend.sh:
  - test/gas_frontend.S, assembled by pxx and by gas and linked by gcc with
    test/gas_frontend_main.c, prints the same in both;
  - for test/gas_frontend_code32.s, the instruction text and every
    relocation match gas, after normalising encoding forms (moffs vs SIB,
    81 vs 83, rel8 vs rel32). The `.multiboot` bytes are identical;
  - the `.code32` REX and rip refusals.
- Gibux 974ce90 (plus the peer's uncommitted tree): C, boot.S and entry.S
  all by pxx, linked by `pascal26 --link --freestanding`, boots hello and
  test-sh, with qemu status 33 four times out of four.

## Not done

- No rel8 relaxation, so code is a few bytes bigger than gas's.
- No `.irp`, `.if`, `.code16` or Intel syntax.
- Indirect branches only through a register (`jmp *%rax`).
- x86-64 only.
- Hosted `pascal26 --link` still refuses `.rodata`; only
  `--link --freestanding` lays it out.
