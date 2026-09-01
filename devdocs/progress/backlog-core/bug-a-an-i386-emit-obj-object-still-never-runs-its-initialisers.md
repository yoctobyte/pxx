---
slug: bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers
track: A
prio: 45
type: bug
status: new
blocked-by: []
owner: ""
created: 2026-09-01
found-by: frankA (while fixing the x86-64 half)
summary: "x86-64 --emit-obj objects now run their file-scope initialisers and program body through .init_array/.fini_array; i386, xtensa and riscv32 do not, because only writeELFRelX64General emits those sections. Measured on i386: test_emit_obj_386_exe still answers `45 pxx-emit-obj` where the x86-64 rows now answer `done99 pxx-emit-obj` -- the same source, the same caller, a different world. Not a regression: those targets were never right, and the x86-64 fix made the gap VISIBLE by making one target correct. The Pascal frontend's thunk emission is target-gated to x86-64 for a hard reason -- EmitSharedThunkPrologue emits raw x86-64 pushes -- so this needs both a per-target thunk prologue and .init_array in writeELFRel386General (SHT_INIT_ARRAY = 14, SHT_FINI_ARRAY = 15, R_386_32 rather than R_X86_64_64, and SHT_REL so the addend lives in the section bytes)."
---

# An i386 --emit-obj object still never runs its initialisers

The sibling the x86-64 fix left behind, filed rather than left implicit because
`test-emit-obj` now carries two different expected values for the same source
and a reader is owed the reason.

## Measured

    x86-64 object, gcc host    done99 pxx-emit-obj    (body ran)
    i386 object, gcc -m32 host      45 pxx-emit-obj    (body did not)

Same `test/test_emit_obj.pas`, same caller. `test_emit_obj_x64_exe` and
`test_emit_obj_386_exe` disagree on purpose and the Makefile says so at the i386
row.

## Two pieces of work, and the first is the one that bites

1. **A per-target thunk prologue.** `EmitSharedThunkPrologue` (symtab.inc) emits
   raw x86-64 pushes. The Pascal call site in `pasparser_prog.inc` is gated on
   `TargetArch = TARGET_X86_64` for exactly this reason — ungated, it splices
   x86-64 bytes into an i386, xtensa or riscv32 object. Anyone widening the gate
   must widen the emitter first. This was nearly shipped ungated; the gate is
   load-bearing, not defensive.
2. **`.init_array` in `writeELFRel386General`**, mirroring the x86-64 writer:
   `SHT_INIT_ARRAY` = 14, `SHT_FINI_ARRAY` = 15, appended after `.shstrtab`'s
   index so no existing section index moves. The relocation differs — i386 is
   `R_386_32` and `SHT_REL`, so the addend lives in the section bytes rather
   than in the relocation.

xtensa and riscv32 go through `writeELF32Rel` and have the same gap. Whether
they want it is a separate question: an ESP image's startup is not a hosted C
runtime, so there may be nothing there to walk `.init_array` at all. Do not
assume the x86-64 answer transfers — see the S lane's note that ESP is not a
Unix.

## Where the x86-64 half landed

`41b08f2bf` (writer + C frontend), `c1bb99ec2` (no thunk when there is nothing
to initialise), and the Pascal arm with
`decide-a-should-a-pascal-program-compiled-to-an-object-run-its-main-body-when-a-foreign-program-loads-it`.
