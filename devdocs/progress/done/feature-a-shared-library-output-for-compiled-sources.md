---
track: A
prio: 50
type: feature
status: done
found: 2026-08-31
found-by: frankC
owner: frankA
blocked-by: []
summary: "DONE 2026-09-01 (0419bab94). --shared now builds a real x86-64 shared library from a compiled source (Pascal/C/NilPy): it LINKS with ld and LOADS with dlopen, exports the C-convention routines, and runs virtual dispatch, the pxx heap, managed strings and calls out to libc from inside. It was blocked on the backend exactly as this ticket said -- a .so is relocated at load, so the absolute operands -no-pie rescued in an object could not work here -- and unblocked by feature-a-x86-64-object-output-is-position-dependent. CORRECTION to this ticket: it said compiler.pas restricts --shared to .asm sources 'in the option handler'. It does not; the handler carries a COMMENT saying so and no check, so a compiled source already reached writeELFSharedX64 and got a structurally valid ET_DYN with zero dynamic symbols, zero relocations and no .bss. Four changes: exports from the same ObjProcIs* predicates --emit-obj uses; a .bss past end-of-file (memsz > filesz); R_X86_64_RELATIVE + DT_RELACOUNT for DataPtrFix and MethodFixups, the only absolute pointers left now that code is rip-relative; and TEN SECTION HEADERS, which no loader reads but which ld requires -- without them `gcc prog.c ./lib.so` says 'file in wrong format' while dlopen of the same file works. Also NOT small: the ticket predicted it would be."
---

# `--shared` for compiled sources, not just `.asm`

Deferred by [[meta-a-pxx-produces-linkable-code]] until the object writer's
shape was known.

## Why this is not the same job as the `.o`

The general x86-64 **object** writer landed with an absolute relocation model
and a documented `-no-pie` requirement. That trade is available because a
non-PIE executable chooses its own load address.

**A shared library does not.** It is relocated at load time by definition, so
the same absolute operands that a `-no-pie` link resolves cannot work here at
all. `writeELFSharedX64`'s own comment states the property it depends on: the
`.asm` frontend's addressing *"is already position-independent by
construction — there is no absolute-address operand form in this frontend at
all"*, so it emits zero `R_X86_64_RELATIVE` relocations. `EmitDataRef` and
`EmitGlobRef` are precisely that missing form.

So the blocker is backend work — [[feature-a-x86-64-object-output-is-position-dependent]] —
and not writer work. Either the backend grows a rip-relative global-reference
form, or the `.so` writer grows `R_X86_64_RELATIVE` emission for every
`Fixups`/`GlobFix`/`DataPtrFix`/`MethodFix` site plus a `DT_RELA`/`DT_RELACOUNT`
pair. **The second is the cheaper of the two and should be priced first** — it
is writer-local, it reuses the relocation inventory `writeELFRelX64General`
already walks, and it does not move a single instruction.

Do not start here expecting the `.o` work to carry over; the export surface and
symbol partition do, the relocation model does not.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]


## Resolved — 2026-09-01, Track A (frankA), `0419bab94`

Binary `ac47455d7c6c`. The blocker,
[[feature-a-x86-64-object-output-is-position-dependent]], landed first in
`d0537380a` / `44b256356` / `a3b1af61a`.

### What works

```
pascal26 --shared mylib.pas mylib.so
gcc main.c ./mylib.so -o prog        # or dlopen at run time
```

| consumer | result |
| --- | --- |
| `dlopen` + `dlsym` + call | virtual dispatch, heap, strings, extern GOT — all correct |
| `gcc main.c ./lib.so` | links, runs |
| `.asm` frontend `--shared` (regression) | still builds, dlopens, runs — and is now linkable too |

### Two things this ticket got wrong, both worth recording

**1. "compiler.pas says so in the option handler."** It does not. The handler
has a *comment* saying `--shared` is `.asm`-frontend only, and no check. So a
compiled source already reached `writeELFSharedX64` and came out as a valid
`ET_DYN` exporting nothing — which is worse than a refusal, because it looks
like a build that worked. A comment recording a restriction is not the
restriction.

**2. "this one is small afterwards."** The relocation model was the blocker, as
stated, but three more things were missing and none of them is in this ticket:
the export list, `.bss`, and section headers.

### The four changes

- **Exports** from `ObjProcIsDefined`/`ObjProcIsExported` — the same predicates
  `--emit-obj` uses, so a `.so` and a `.o` cannot disagree about who is
  exported. `GLOBAL FUNC` with `st_size`, not `GLOBAL NOTYPE`. Exporting nothing
  is refused with a message.
- **`.bss`**, which this layout did not have at all. Past end-of-file with
  `memsz > filesz`; placing it last keeps `vaddr == file offset` for everything
  *in* the file, which the writer assumes everywhere.
- **`R_X86_64_RELATIVE`** for `DataPtrFix` (data→data) and `MethodFixups`
  (vtable slots, data→code), emitted first with `DT_RELACOUNT`. Code
  contributes none — that is what the blocker ticket bought.
- **Ten section headers.** No loader reads them, which is how the `.asm` path
  managed without any. `ld` requires them: `gcc prog.c ./lib.so` gives *file in
  wrong format* while `dlopen` of the identical file succeeds. Measured — that
  was the state after the first three changes, and it is the difference between
  a dlopen-able artefact and a shared library.

The `.asm` and compiled paths are **one** path over an export list built up
front, not a branch at each of the six use sites.

### The control, and the aim check it produced

"The `.so` loads and runs" is exactly the claim an empty population produces: a
library with no absolute data pointers would load and run correctly with no
relocations at all.

| arm | result |
| --- | --- |
| suppress the RELATIVE entries, rebuild, run the dlopen host | **SEGFAULT** |
| restore | `SHARED LIB OK` |

So the Makefile asserts `RELACOUNT > 0` **before** any behavioural row, and
says why in the recipe. Without it, a test source that quietly stopped
containing an absolute data pointer would go on reporting success —
the third time in this ticket family that the population, not the instrument,
was what needed checking.

`test/test_shared_lib.pas` is written to contain the classes it tests: a
virtual method, `SetLength`, `AnsiString` concatenation, an external `libc`
call, and a string literal returned as `PChar`. Its header says why each is
there rather than in a smaller program.

### Not done here

A Pascal `library` unit with an `exports` clause — `library` is not a keyword
today, so a shared library is written as a `program` with `cdecl` routines and
an empty main body. i386 `--shared` is refused (the backend is still
position-dependent there). No `DT_SONAME` or versioning.

## Log
- 2026-09-01 — resolved, commit 84a4fda97.
