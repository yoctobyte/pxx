---
track: A
prio: 40
type: bug
status: done
found: 2026-08-30
found-by: claude-T
owner: frank-optimize-b4
---

# `--emit-obj` on x86-64 emits an object that exports nothing

Same source, same compiler, one flag apart. `test/test_emit_obj.pas`:

| target | sections | symbols |
| --- | --- | --- |
| riscv32 | `.text .rela.text` **`.data(0xb18) .rela.data .bss(0xa530)`** `.symtab(0xa60)` | **166**, incl. `app_main` FUNC GLOBAL |
| xtensa | `.text .rela.text` **`.data(0x840) .rela.data .bss(0xa530)`** `.symtab(0xab0)` | full |
| **x86-64 `--emit-obj`** | `.text` `.rela.text(size 0)` `.symtab(0x60)` | **4** |

The four x86-64 symbols are the null entry, a `.text` section symbol, and the
two UND imports. **There is no defined symbol at all** — no `app_main`, no
function. Nothing can link against this object because it exports nothing, and
it carries no data, no bss and zero relocations.

## It reports success, with figures the file does not contain

```
$ compiler/pascal26 -Fulib/rtl --emit-obj test/test_emit_obj.pas /tmp/teo.o
ok: /tmp/teo.o  [code=61709B  data=2864B  bss=42332B  procs=132]
```

`data=2864B bss=42332B procs=132` — and the object has no `.data`, no `.bss`,
and one defined symbol short of none. The summary line describes a compilation
that happened; the file describes what was written; nothing reconciles them.

## Why nothing caught it

`test-emit-obj` is a real, careful test — it asserts both directions of the
external-name aliasing bug, which is the kind of negative most tests skip. It
just never runs this path: every one of its assertions is against
`--target=riscv32` or `--target=xtensa`, and neither uses the `--emit-obj` flag.

> A test that exists, passes, and is unwired to this target — face 222,
> exactly. The feature is advertised generally in `--help` and in
> `docs/index.md` (*"also emit a relocatable object (`--emit-obj`, `.o`) for
> linking with other..."*), and is broken on the host architecture.

## Repro

```
compiler/pascal26 --target=riscv32          test/test_emit_obj.pas /tmp/rv.o
compiler/pascal26 -Fulib/rtl --emit-obj     test/test_emit_obj.pas /tmp/x64.o
readelf -SW /tmp/rv.o  | grep -c '\.data\|\.bss'     # 3 (.data .rela.data .bss)
readelf -SW /tmp/x64.o | grep -c '\.data\|\.bss'     # 0
readelf -sW /tmp/x64.o | grep -c 'FUNC'              # 0
```

Measured at `46316ba8b`, binary `1ff8acbe123b` (built at `5944ee686`).

## Scope note — I have NOT established what the right behaviour is

Two readings, and choosing between them is Track A's call, not mine:

1. The x86-64 relocatable writer is incomplete, and should emit `.data`,
   `.bss`, `.rela.*` and a real symbol table as riscv32/xtensa already do.
2. `--emit-obj` was only ever meant for the embedded targets, and the x86-64
   path should **refuse** rather than emit a silently unusable object.

Either is defensible. What is not defensible is the current state: an
advertised flag that reports success and writes an artifact that cannot be
used, on the default target. If (2), the fix is an error message and a docs
line, and it is cheap.

## Provenance

Found while investigating whether an external ELF-layout oracle
([[feature-t-a-second-oracle-dimension-section-alignment]]) had anything left to
check after Track A's `df98fea47` alignment invariant landed. It did not, for
alignment — but the objects it looked at on the way turned out to be empty.
T owns the tool, never the bug.

## Resolved 2026-08-30 by frank-optimize-b4 — refusal, with the reason measured

**Neither of the two readings above is what is going on, and the third one
changes the fix.** There are two object writers and `compiler.pas` picks
between them by ARCHITECTURE:

| writer | symbol source | relocation source | refuses |
| --- | --- | --- | --- |
| `writeELF32Rel` | procs, `app_main`, externs | `FixCount`, `GlobFixCount`, `DataPtrFix`, `MethodFix` | anything but xtensa/riscv32 |
| `writeELFRelX64` | **`AsmGlobalSym*`** (`.asm` `global` labels) | **`AsmObjCall*`** (`.asm` `call <extern>`) | anything but x86-64 |

`writeELFRelX64` is the **`.asm` frontend's** writer — its own first line says
`'--emit-obj: .asm frontend object output is x86-64 only'`. For a `.asm` source
it is complete: data is appended into `Code[]` and addressed as part of `.text`
(`dataBase := CodeLen`, `asmfront.inc`), so there is nothing else to describe.
A Pascal program has no `AsmGlobalSym`s and no `AsmObjCall`s, so the writer
faithfully wrote everything it knew, which was nothing.

So reading 1 is wrong — the x86-64 writer is not an incomplete general writer,
it is a **complete narrow one being handed the wrong programs**. And reading 2
is wrong — `--emit-obj` is not embedded-only, it is `.asm`-only on x86-64 and
general on the two ESP targets. **There has never been a general x86-64
relocatable writer for the dispatch to be incomplete against.**

### The fix

Refuse, in `writeELFRelX64`, in terms of **what the object would have to
carry** rather than which frontend produced it — so a `.asm` source that needs
only text, `global` labels and extern calls still works exactly as before:

    if (BSSSize > 0) or (FixCount > 0) or (GlobFixCount > 0) or
       (DataPtrFixCount > 0) or (MethodFixCount > 0) or (ProcAddrFixCount > 0)
    ...
    if (AsmGlobalSymCount = 0) and (ProcCount > 0)

Measured: `test_emit_obj.pas` on x86-64 now exits 1 with the reason and
**writes no file**; `test_asm_obj.asm` still emits its object with
`asm_obj_add` and `asm_obj_start` GLOBAL DEFAULT in `.text`; riscv32 and xtensa
are untouched (`data=2840B bss=42288B procs=168` and a real symtab, as before).

The error replaces the `ok:` line rather than accompanying it, per the
condition on this ticket. One blemish inherited from every other writer error
in this file: `Error()` attaches the lexer's last position, so the message is
prefixed `pascal26:2:` and followed by an `in:`/`near:` pointing at
`builtinheap.pas`. That is misleading for a link-stage failure and is a
pre-existing convention, not something this fix introduced — worth its own
ticket if anyone is annoyed by it.

### Wired, and this was the actual root cause of the invisibility

`test-emit-obj` now begins with x86-64 rows, ahead of the riscv32/xtensa ones:
the refusal's exit status AND the absence of an `ok:` line asserted separately,
no leftover `.o` on disk, and the `.asm` object still exporting its globals.
Face 222 exactly — a rule named for a flag it never passed.

**Worth recording against face 229:** the first version of that new row was
`... > log 2>&1 || true; echo "rc=$$?"`, which captures **`true`'s** status and
passes on a success. I wrote the defect face 229 describes, inside the test for
this bug, hours after writing the face. Caught by running it and reading `rc=0`
where `rc=1` belonged, not by re-reading the line. The idiom is genuinely
attractive under a shell that aborts on non-zero, and `;` is sufficient.

### Follow-up

`feature-a-a-general-x86-64-relocatable-object-writer` [A p30] — the port, with
the design question that must be answered first: the x86-64 backend emits
ABSOLUTE 32-bit global references (`Patch32`), which become `R_X86_64_32` and
only link in a non-PIE, below-4G link. Whether to emit those and document
`-no-pie`, or teach the backend a PC-relative form under `--emit-obj`, decides
the writer's data structures and is backend work rather than writer work.

Docs corrected in the same pass (`docs/index.md`, `docs/reference/cli.md`) and
`--help`, since this commit is what makes the old wording false.

## Log
- 2026-08-30 — resolved, commit 1befc225d.

### The measured matrix, at this fix's binary — both axes

frankD measured the target axis against `pinned` while this was in flight and
found `--emit-obj` refused on i386/aarch64/arm32, so *"on any target"* in the
docs was false on three of six. This fix adds a **second axis** that no
instrument carried: source kind. Measured here, `dba7f59f2e9b`:

| target | Pascal source | `.asm` source |
| --- | --- | --- |
| x86-64 | **error** | ok |
| riscv32 | ok | error |
| xtensa | ok | error |
| i386 / aarch64 / arm32 | error | error |

Three instruments described this flag and all three were wrong differently:
the docs said "any target", `writeELF32Rel`'s diagnostic said "only
xtensa/riscv32" while x86-64 had a writer, and the x86-64 writer said nothing
at all and wrote an empty object. The message is corrected in the same commit
(`bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64`) and the
docs now state both axes, on top of frankD's measurement rather than instead
of it.
