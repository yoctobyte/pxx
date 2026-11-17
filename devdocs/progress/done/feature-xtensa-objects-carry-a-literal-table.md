---
track: ESP
tags: [esp, xtensa, elf, pie, gibux, ld]
prio: 30
type: feature
blocked-by: []
summary: "pxx's xtensa --emit-obj objects carry .xt.lit and .rela.xt.lit, the literal table gcc's objects have: each run of relocated literal words in .text and .iram1.text, from ObjXtLitPlan in both ELF32 writers. Without it, ld -pie refused every literal with 'dangerous relocation: dynamic relocation in read-only section', because a dynamic relocation in read-only code is accepted only inside a listed literal range. With it, plus --no-ro-data, a pxx object links into the PIE Gibux loads: ET_DYN, no PT_INTERP, only R_XTENSA_RELATIVE."
status: done
owner: unassigned
---

# xtensa objects carry a literal table

The Gibux kernel session asked whether pxx can produce its user programs.

## Before
- Linking a pxx object with `ld -pie --no-dynamic-linker -T prog.ld` failed at every relocated literal (396 in a crtl hello) with "dynamic relocation in read-only section".
- Renaming .text to .literal did not help. ld goes by the .xt.lit property table, not by the section name.

## Fix
ObjXtLitPlan (elfwriter.inc) marks every relocated word: Fixups, GlobFix, DynCall, and in the IRAM writer also IramCallFix and ProcAddrFix. On xtensa each of those is an l32r literal. It merges the marks into runs, and both writers append `.xt.lit` (address, size pairs) and `.rela.xt.lit` (R_XTENSA_32 against the .text or .iram1.text section symbol). These go after every fixed section index, so no existing index moves.

## What else is needed for a PIE
`--no-ro-data`: a pointer constant in a read-only .rodata is refused for the same reason. A recipe and what's left are in feature-xtensa-gibux-user-programs-as-et-dyn-pie.

## Test
tools/check_xtensa_pie_link.py links test/c_xtensa_pie_hello.c with test/xtensa_pie_prog.ld and requires:
- ET_DYN, no PT_INTERP, and only R_XTENSA_RELATIVE relocations.
- An R+X segment that holds .text alone.
- A linked .text equal to the object's except at the relocated words. xtensa ld relaxes by default, and it must not move or drop literals it sees no l32r relocation for. Measured: only the 396 relocated words differ.

The old compiler fails at ld. The ld-linked freestanding, vfork and section-attribute checks still pass with the table present.

## Also found
pxx's C frontend does not take explicit register variables (`register long a2 __asm__("a2")`), which is how Gibux's own hello.c makes syscalls. Its inline asm also pins only six registers (a3..a6, a10, a11), so a four-argument syscall written as operand asm with clobbers is refused. crtl's syscall() covers programs that link crtl.
