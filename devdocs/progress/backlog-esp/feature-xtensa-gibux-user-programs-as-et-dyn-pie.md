---
track: ESP
tags: [esp, xtensa, gibux, pie, elf, linux-abi]
prio: 60
type: feature
blocked-by: []
summary: "pxx should build Gibux user programs on ESP32-S3. The shape is a 32-bit ET_DYN with no PT_INTERP and only R_XTENSA_RELATIVE relocations, using Linux xtensa syscalls (number in a2, arguments in a6 a3 a4 a5 a8 a9). It needs separate PT_LOADs: .text+.literal (with the ELF and program headers) in R E, everything else in RW, because the S3 runs SRAM through an instruction-bus alias that allows aligned 32-bit loads only. The gcc reference is ~/gibux/tests/xtensa/prog.ld with -fPIE -pie --no-dynamic-linker -nostdlib. The GNU ld route WORKS since feature-xtensa-objects-carry-a-literal-table (2026-11-17): --emit-obj --no-ro-data, then ld -pie --no-dynamic-linker -T prog.ld. Left: a C entry that hands argc/argv/environ to main(), and a first run on Gibux."
status: open
owner: unassigned
---

# Gibux user programs on xtensa: ET_DYN PIE

Requested on 2026-11-17 by the Gibux kernel session. It is for after the kernel builds with pxx; there is no rush.

## Target shape
- 32-bit ELF, ET_DYN, no PT_INTERP, no dynamic linker. The only relocation type is R_XTENSA_RELATIVE, and the Gibux loader applies those.
- Syscalls use the Linux xtensa ABI: the number in a2, the arguments in a6, a3, a4, a5, a8, a9, then `syscall`.
- Two PT_LOADs:
  - R E: the ELF header, the program headers, .text and .literal, and nothing else.
  - RW: .rodata and everything else.
- The loader maps the code segment through the S3 instruction-bus alias of SRAM. That alias allows aligned 32-bit loads only, so no byte or halfword data may sit in the code segment. Inline L32R literal pools are 32-bit aligned loads, so they are fine. String and table constants must go to RW.

## Reference
- ~/gibux/tests/xtensa/prog.ld
- gcc flags: `-fPIE -pie --no-dynamic-linker -nostdlib`

## Starting points in pxx
- The freestanding ESP object path (EspFreestandingObj, 15f818e2d6) already produces bare-runtime xtensa code. Linking it with GNU ld and prog.ld may be the first experiment, before pxx writes the ET_DYN itself.
- Open questions:
  - Absolute data addresses in literals each need an R_XTENSA_RELATIVE.
  - The windowed ABI must be checked against the Gibux user entry.

## Status 2026-11-17: the ld route works
pxx objects now carry an .xt.lit literal table (feature-xtensa-objects-carry-a-literal-table). With it, GNU ld accepts their literal relocations in a PIE:

    pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh --xtensa-abi=windowed --no-ro-data --emit-obj prog.c prog.o
    xtensa-esp32s3-elf-ld -pie --no-dynamic-linker -T prog.ld prog.o -o prog

The result is ET_DYN with no PT_INTERP and only R_XTENSA_RELATIVE relocations, and .text sits alone in the R+X PT_LOAD. `--no-ro-data` is needed because without it pointer-holding constants land in a read-only .rodata, which ld also refuses to give dynamic relocations. In prog.ld .rodata goes to the RW segment anyway, so it costs nothing there. test/c_xtensa_pie_hello.c is the first program, and its entry is a C `_start` that never returns.

Left:
- **A C entry for main().** A `_start` that reads argc/argv/envp from the initial stack, sets environ and calls main, as the hosted call0 program stub does. That is also what BusyBox needs.
- **A run on Gibux.** qemu-user cannot run it, because nothing applies the RELATIVE relocations.
- **pxx writing the ET_DYN itself** (no GNU ld). Optional now.
