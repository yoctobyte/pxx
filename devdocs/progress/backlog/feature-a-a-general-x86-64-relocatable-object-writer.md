---
track: A
prio: 30
type: feature
status: backlog
found: 2026-08-30
found-by: frank-optimize-b4
---

# There is no general x86-64 relocatable object writer, and that is the gap

`--emit-obj` now **refuses** a Pascal/C/NilPy program on x86-64
(`bug-a-emit-obj-on-x86-64-produces-an-object-with-no-symbols-data-or-relocations`)
instead of writing an object that exports nothing. This ticket is the other
half: making it work.

## What the measurement actually found — neither of the two readings on offer

The bug ticket set out two possibilities: the x86-64 relocatable writer is
incomplete, or `--emit-obj` was only ever meant for the embedded targets. It is
neither.

There are **two** object writers, and the dispatch picks between them by
**architecture** when the discriminator should be *what the object has to
carry*:

| writer | emits | refuses |
| --- | --- | --- |
| `writeELF32Rel` | the general object: procs as symbols, `app_main` exported, `.data`, `.bss`, `.rela.text`, `.rela.data` | anything but xtensa / riscv32 |
| `writeELFRelX64` | `.text`, a symbol per **`.asm` `global` label**, UND externs, one reloc per `.asm` `call <extern>` | anything but x86-64 |

`writeELFRelX64` is the **.asm frontend's** writer — its symbol source is
`AsmGlobalSym*` and its relocation source is `AsmObjCall*`, and its own first
line says so. For a `.asm` source that is complete and correct: data is
appended into `Code[]` and addressed as part of `.text`
(`dataBase := CodeLen`, `asmfront.inc`), so there is nothing else to describe.

`compiler.pas` sent every x86-64 object request there, including Pascal ones.
So there has never been a general x86-64 object writer to be incomplete. The
feature was advertised generally, implemented for two 32-bit targets, and the
default target fell into a writer built for a different frontend.

## The work

Port `writeELF32Rel` to ELF64 / x86-64: `Elf64_Shdr`, `Elf64_Sym`,
`Elf64_Rela`, and the x86-64 relocation types for what the backends record —
`FixCount` (8-byte absolute data refs), `GlobFixCount` (4-byte absolute global
refs), `DataPtrFixCount` / `MethodFixCount` (data-to-data pointers).

## The one real design question, and it should be answered before any code

**The x86-64 backend emits ABSOLUTE 32-bit references to globals**
(`Patch32(GlobFix[i].CodePos, addr)`). In an executable that is fine — we
choose the load address. In a relocatable object it becomes `R_X86_64_32`,
which a linker can only satisfy in a **non-PIE link with everything below
4 GiB**. Modern toolchains default to PIE, so an object full of `R_X86_64_32`
will fail to link for many users with a message about recompiling with `-fPIC`.

The choices are (a) emit `R_X86_64_32` and document the `-no-pie` requirement,
(b) teach the backend a PC-relative global-reference form under `--emit-obj`
and emit `R_X86_64_PC32`, or (c) both, selected by a flag. (b) is the one that
produces objects that link the way people expect, and it is real backend work
rather than writer work — which is why this ticket is filed rather than done.
**Answer this before writing the writer**: the relocation model decides the
data structures, not the other way round.

## Priority

p30. Nothing is broken now that the refusal is loud, the ESP-IDF path — the one
with a real consumer — works on both its targets, and the `.asm` path works.
This is capability, not repair. Raise it the moment something actually needs to
link a pxx object into an x86-64 build.
