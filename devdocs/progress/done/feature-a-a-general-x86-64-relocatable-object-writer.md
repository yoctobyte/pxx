---
track: A
prio: 80
type: feature
status: done
found: 2026-08-30
found-by: frank-optimize-b4
summary: "DONE, landed 41045d7b4. writeELFRelX64General writes the general ELF64/x86-64 object (procs as symbols, .data, .bss, every backend relocation kind) and --emit-obj now dispatches on what the object has to CARRY (AsmGlobalSymCount) rather than on architecture. MEASURED, not inferred: a gcc-built main links a pxx object and calls into it -- Pascal and C sources, int and double signatures, strings through the pxx heap, and pxx calling out to libm sqrt resolved by the system linker; clang and tcc link the same object and agree. External calls needed NO backend change: an x86-64 external call is already `call [abs32]` through a GOT slot in our OWN .data, so in an object it is two ordinary relocations and the LINKER fills the slot. Two decisions stated rather than defaulted: the export surface is the C-convention routines (ProcCdecl) and everything else is LOCAL, so an object cannot collide with its host over an RTL name; and the relocation model is ABSOLUTE, so a link needs -no-pie -- option (b) is filed separately as feature-a-x86-64-object-output-is-position-dependent. The program entry is deliberately NOT exported, so a linked-in object runs NO initialisation -- the test pins the VALUE that proves it. xtensa/riscv32 --emit-obj and the .asm writer are untouched and re-verified by hand."
owner: frankC
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

## RESOLVED 2026-08-31, frankC — landed 41045d7b4

### The one design question, answered before the code, as the ticket demanded

**(a): absolute relocations, `-no-pie` documented.** `R_X86_64_64` for the
8-byte data operands `EmitDataRef` emits, `R_X86_64_32S` for the 4-byte global
displacements `EmitGlobRef` emits — every x86-64 site is a `[disp32]` SIB form,
which the CPU sign-extends, so `32S` and not `32`.

(b) — a rip-relative form under `--emit-obj` — was **not** bundled in, because
`[rip+disp32]` and `[disp32]` are different ModRM encodings of different
LENGTHS: switching form under a flag moves every subsequent code offset, branch
fixup, proc body address and DWARF range. That is backend work with a real blast
radius sitting behind a writer that is otherwise done, so it is
[[feature-a-x86-64-object-output-is-position-dependent]] — which also prices an
alternative this ticket did not consider: a GOT-style indirection for globals in
object output only, needing no encoding change at all.

The `-no-pie` boundary is not documentation alone. `test-emit-obj` asserts that
a PIE link **fails**, so the day the model changes, something says so.

### The thing that made this small, and the ticket did not foresee it

**External calls needed no backend change.** The work list named four relocation
kinds and did not mention calls; calls looked like the hard part, because the
`.asm` writer reaches externals through `R_X86_64_PLT32` and the general backend
emits no `call rel32` for them at all.

It emits `call qword ptr [abs32]` through a GOT slot the compiler allocates in
its **own `.data`** (`RegisterExternal`). In an object that is two ordinary
relocations — the operand is `R_X86_64_32S` against `.data`, the 8-byte slot is
`R_X86_64_64` against the extern's UND symbol — and the **linker** fills the
slot. No PLT, no new emit mode, no rewriting of the call site. `@extern`
(`EmitExternalProcAddr`) rides the same pair for free.

Verified end to end rather than by inspection: a Pascal object calling `sqrt`
from `libm.so.6`, linked by gcc, returns `pxx_hyp(3,4) = 5.0000`.

### Two decisions the ticket did not raise, stated rather than defaulted

**Export surface = the C-convention set (`ProcCdecl`)** — Pascal `cdecl`, and
every function of a C translation unit — GLOBAL FUNC under its own name.
Everything else defined, including the whole RTL pulled in with it, is LOCAL
FUNC: a debugger sees it, the linker does not, so an object cannot collide with
its host over a name like `WriteLn`. An internal-convention routine exported
under its Pascal name would be *callable and wrong*, which is the failure worth
designing against.

Nothing exported means nothing linkable, and we refuse rather than write it —
the same reasoning as the sibling bug: a file whose failure surfaces at someone
else's link step with no cause attached.

**The program entry is NOT exported.** It sets up globals, runs the body and
exits, so a C caller invoking it would terminate the process rather than return.
The consequence is real and is documented rather than hidden: **a pxx object
linked into a foreign program runs no initialisation.** The regression test pins
the VALUE that proves it — `emit_obj_addup(9)` returns 45, not 54, because `g`
is still 0 — so it would notice if that ever silently changed. A presence check
would not.

Measured and worth knowing: string work through the pxx heap **does** survive
this. A `cdecl` routine that builds an `AnsiString` and returns a `PChar` works
from a gcc-built caller, because the arena is faulted in on demand rather than
at startup.

### The test rows would have stayed green for the wrong reason

`test-emit-obj`'s x86-64 rows asserted the **refusal**, and `test_emit_obj.pas`
has no `cdecl` definition — so the *new* "defines nothing linkable" guard fires
on it and all four assertions still pass. Correct about something else, and it
would have shipped a feature with no test at all.

Rewritten to assert the object, the export surface (with the negative — `AddUp`
must NOT be global), the external UND link names and the GOT-slot relocation,
then the link and the **run** under a gcc-built `main`. Everything above that
last row is byte inspection, which is exactly what let the old broken object
pass as plausible.

The refusal keeps a **positive control** of its own — `test_emit_obj_noexport.pas`,
a case it must reject — because a guard that cannot fail is not a guard and it
prints PASS.

### A comment I nearly published that was false

The first draft of the `SymOffIsData` arm cited a bug in the ELF32 sibling for
reading the biased offset raw. **It is not a bug.** The promotion that creates a
data-resident global bails out under `EmitObjMode` (`symtab.inc`, `if
EmitObjMode or EmitSharedMode then Exit`), so no object reaches it on any
target. The comment now says the true and more useful thing: that arm is the
missing half the refusal names, so lifting it on x86-64 is a symtab question,
not a writer one.

### Verified

- `make compiler/pascal26` — `converged after 1 round(s)`.
- `tools/gate.sh quick` — GREEN, exit 0, 10/10 rows.
- By hand, the gate this must not break: `.asm` frontend `--emit-obj`;
  riscv32/xtensa `--emit-obj` for `test_emit_obj.pas` and `cxtensa_obj.c`;
  xtensa windowed ABI. All green, including the `ext_aliased_link` negative.
- Three independent linkers on one object — `gcc -no-pie`, `clang -no-pie`,
  `tcc` — all print `45 pxx-emit-obj`. `ld.lld` is not installed on this box.
- Exports survive DCE at `-O0/-O1/-O2/-O3` (checked, because an unreferenced
  `cdecl` routine is exactly what a dead-code pass would remove).
- `tools/doclinks.py`, `tools/docsnip.py`: 0 broken.

### Docs

`docs/reference/objects.md` (new), linked from the reference index and from the
`--emit-obj` row of `docs/reference/cli.md`, whose old text — *"x86-64 emits
objects for `.asm` sources only"* — was the true-then, false-now half of the
pair the sibling bug named. The compiler's own ELF32 refusal message said the
same thing and is fixed with it.

## Log
- 2026-08-31 — resolved, commit ed5a62e4d.
