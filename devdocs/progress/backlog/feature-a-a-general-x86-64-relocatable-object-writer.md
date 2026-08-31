---
track: A
prio: 80
type: feature
status: backlog
found: 2026-08-30
found-by: frank-optimize-b4
summary: "RE-PRICED 30 -> 80 by the owner 2026-08-31: top priority, above further bug fixing. There is no general relocatable object writer for x86-64/i386/arm32/aarch64 -- --emit-obj writes general objects for xtensa|riscv32 only, on x86-64 it takes .asm sources alone, and --shared is .asm-frontend only (compiler.pas:1238). The diagnosis is neither of the two readings the bug ticket offered: there are TWO object writers and the dispatch picks between them by ARCHITECTURE when the discriminator should be what the object has to carry. The ABI machinery it needs already exists -- DT_NEEDED/dynsym/GOT-indirect in elfwriter.inc, working foreign callbacks via gtk3.pas:47, per-function call type in ProcCdecl -- so this is the ET_REL writer alone. Beyond the capability, it is what makes the C-ABI convention on the three divergent targets externally checkable at all. Umbrella: meta-a-pxx-produces-linkable-code. Do not break xtensa/riscv32 emit-obj: it is the only evidence any of this works."
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

## TRIP-WIRE — when this extends to aarch64, an ABI mismatch goes live. frankC, 2026-08-30

Placed here rather than in a Track C ticket because **there is no defect today**;
it is a hazard that this ticket's own work arms. Whoever generalises the object
writer for x86-64 is the next person to look at aarch64, and this is what they
need to know before they do.

### The hazard

On aarch64 a pxx-compiled **C** function's prologue is **positional**, while
pxx's own external-call path is **AAPCS** (`ir_codegen_aarch64.inc:2985` —
independent lo/hi counters, `fmov d[hi]` / `fcvt s[hi]`). `cparser.inc`'s aarch64
param spill mirrors the *Pascal* aarch64 spill rather than AAPCS. Observed by
frankA while giving the cross targets a real C-convention prologue; measured
here.

### Why it is inert today — and NOT for the reason it first appears

The tempting summary is *"it only bites where a real C caller calls into
pxx-compiled C, and there is no such caller."* **That is false and should not be
recorded.** Real C callers invoke pxx-compiled C on aarch64 today, every time a
libc callback runs: `qsort`, `bsearch`, `pthread_create`'s start_routine,
`signal` handlers, `atexit`. The class is reachable. The safety comes from
somewhere else:

**Positional and AAPCS COINCIDE for all-integer/pointer signatures.** AAPCS
assigns integers to x0-x7 in order, which *is* positional. They diverge only for
**mixed int/float** arguments, because that is when AAPCS's independent GP and FP
counters stop tracking the argument index. No standard libc callback has that
shape — they take pointers and ints.

So the safety is a property of the **signatures**, not an absence of callers.
The distinction is the whole reason this note exists: *"nothing can reach it"* is
falsified the day somebody writes one callback with a `double` in it, and nobody
re-checks a note that claims nothing can reach it. A condition invites
re-checking; an absence does not.

### The two conditions that make it live

1. **An aarch64 object writer landing** — then an external toolchain links
   directly against pxx-compiled aarch64 code, with arbitrary signatures. This
   ticket is the work that leads there.
2. **Any callback signature carrying floating-point arguments.**

### Measured, 2026-08-30, compiler `f2bfbb3c94a5`

Route 1 is closed outright today, by the compiler's own refusal:

```
$ pascal26 --target=aarch64 --emit-obj t.c t.o
error: --emit-obj: a general relocatable object ... is emitted for
       --target=xtensa and --target=riscv32; x86-64 emits objects for .asm
       sources only; i386, arm32 and aarch64 have no object writer
```

riscv32 emits one fine; x86-64 refuses for general programs, which is this
ticket. **aarch64 has no object writer at all**, so nothing external can link
against pxx-compiled aarch64 code by any route.

And the current behaviour is correct, on a function with mixed `int`/`double`
parameters called three ways — directly, through a function pointer, and via a
libc callback — run through `tools/run_target.sh` (a bare `qemu-aarch64` on a
dynamically-linked binary fails with `Could not open
/lib/ld-linux-aarch64.so.1`, which looks like a red and is not one):

| | aarch64 | gcc oracle |
| --- | --- | --- |
| direct | 15.0 | 15.0 |
| via function pointer | 15.0 | 15.0 |
| `qsort` callback | 12345 | 12345 |

Self-consistency confirmed, and the libc-callback path confirmed working.

### What to do when you get here

Before extending object emission to aarch64, make `cparser.inc`'s aarch64 param
spill AAPCS rather than positional — or establish that it already is, since
frankA's observation was a **reading of the code and not a measurement**, and the
table above only proves the cases that coincide. The falsifying test is a
function with mixed int/float parameters called from a *genuinely external* C
caller, which is precisely what this ticket makes constructible for the first
time.

## Umbrella

[[meta-a-pxx-produces-linkable-code]] — priced above bug fixing by the owner, 2026-08-31.
