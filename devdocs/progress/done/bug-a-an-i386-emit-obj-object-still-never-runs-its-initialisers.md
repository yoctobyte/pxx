---
slug: bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers
track: A
prio: 45
type: bug
status: done
blocked-by: []
owner: frankA
created: 2026-09-01
found-by: frankA (while fixing the x86-64 half)
summary: "FIXED for i386, both frontends. .init_array/.fini_array added to writeELFRel386General and an i386 arm added to the thunk prologue/epilogue. MEASURED: the Pascal object now answers `done99 pxx-emit-obj` under a gcc -m32 host where it answered `45`, and the C object answers `envcount=73 data=pxx-c-data` where it answered `envcount=-1 data=(NULL)`. Three psABI differences from the x86-64 twin, none cosmetic: 4-byte entries, R_386_32 against the .text section symbol, and SHT_REL carrying no addend -- so the thunk offset goes in the SECTION BYTES and a writer that zeroed them the way the x86-64 one correctly does would hand the C runtime a null pointer while passing every other assertion. envp also arrives differently (rdx vs the stack), which the C thunk now knows. xtensa/riscv32 remain out of scope and out of the gate; EmitSharedThunkPrologue REFUSES them rather than falling through to x86-64 opcodes."
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

---

## Resolved 2026-09-01 (frankA)

    Pascal, gcc -m32 host    45 pxx-emit-obj      ->  done99 pxx-emit-obj
    C,      gcc -m32 host    envcount=-1 (NULL)   ->  envcount=73 pxx-c-data

Both arms of the ticket, plus the two pieces of work it named.

**The thunk prologue is now per-target and REFUSES what it does not implement.**
That is the load-bearing half. These are raw opcodes, so a fallthrough splices
x86-64 pushes into an i386 or xtensa object — which is exactly what an ungated
attempt at the Pascal x86-64 arm would have done. The call sites gate on the same
set the emitter implements, and the emitter can now fail loudly if they drift.

**The i386 arithmetic is not the x86-64 arithmetic and must not be copied.**
i386 enters at `esp` 12 mod 16 (the caller aligned to 16, then pushed a return
address); four pushes move it by 16 and leave it 12 mod 16, so the reservation is
12, not 8. And passing envp needs 16 reserved rather than a 4-byte `push`,
because cdecl wants `esp` 16-aligned AT the call with the argument already
placed.

**The SHT_REL difference is the one that would have shipped silently.** With no
addend field the slot must contain the thunk offset itself. Writing zero — the
correct x86-64 habit — produces an object where the sections exist, the
relocation exists, `readelf` looks right, and the C runtime calls a null pointer.
The test asserts the slot is non-zero for that reason, and the assertion was
given a positive control (a synthetic zeroed line, confirmed to be caught).

## Found in passing, filed separately, NOT caused here

`bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations` — an i386 C
object links with `relocation in read-only section .text` and `creating
DT_TEXTREL in a PIE`. Measured on objects built before AND after this work: two
warnings both times, so it is pre-existing. It matters because `-Wl,-z,text`
refuses such a link outright, and the reason nobody noticed is that i386 has no
equivalent of the x86-64 rows asserting `.text` carries no absolute relocation.

## Log
- 2026-09-01 — resolved, commit 3dd98fe32.
