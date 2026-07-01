# `.asm` as a first-class source frontend (assemble + link to object/exe/.so)

- **Type:** feature (frontend / linker) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Relation:** part of [[feature-assembler-first-class-citizen]];
  consumes [[feature-asm-structured-ir-library]]; pairs with
  [[feature-asm-textual-emit-mode]] for round-trip validation.
- **Fast-tracked subset is urgent:** [[feature-asm-mvp-frontend]] cuts a
  minimal straight-line-only (no labels/externs/sections) version of this
  out and asks Track A to land it first — read that one before this if
  you're picking up asm-frontend work now; this ticket is still where the
  full scope (labels, `-c`, `.so`, multi-target) lands afterward.

## Owner split (2026-06-30)

This frontend's eventual backend is the layer-1/layer-2 split: parse `.asm`
text into operands, encode the mechanical part via
[[feature-asmcore-encoder-library]] (Track B, `lib/asmcore/`), resolve
labels/externs/relocations via [[feature-asm-structured-ir-library]] (Track
A). The frontend parser itself (this ticket) and the `ET_DYN` writer gap are
Track A — new compiler entry point + linker work, not library legwork.

## Correction (2026-06-30, same day as filing)

The per-target encode-with-labels-and-relocations engines this frontend would
need as a backend **already exist and don't need to be built**: `compiler/
asmtext.inc` + `asmtext_386.inc`/`asmtext_a64.inc`/`asmtext_arm32.inc`/
`asmtext_rv32.inc`/`asmtext_xtensa.inc` already handle label resolution,
forward/backward jumps, and `@glob`/`@data` relocations for all six targets
(x64, i386, aarch64, arm32, riscv32, xtensa) — see
[[feature-asm-structured-ir-library]] for the full audit. What's genuinely
novel here is the **frontend**: a free-form parser for external `.asm` files
(comments, `section`/`global`/`extern`/`align` directives, multi-line syntax)
feeding into those existing engines — and the `ET_DYN` linker gap below,
which is real and unaddressed by anything found so far.

## Goal

`pxx foo.asm` parses hand-written assembly source the same way `.c` is
already a first-class frontend alongside `.pas` (`compiler/clexer.inc` /
`cparser.inc`), and drives `elfwriter.inc` to produce, depending on flags:

- an object file (`-c` → `ET_REL`),
- a linked executable (`ET_EXEC`),
- a shared library (`ET_DYN`).

## Current state of the linker backend (audited 2026-06-30)

`elfwriter.inc` already has a relocatable `ET_REL` object writer ("Relocatable
ELF32 object writer (feature-elf-rel-writer)") and an `ET_EXEC` writer,
reachable today via the existing `EmitObjMode` compiler flag
(`compiler/compiler.pas`). **`ET_DYN` (`.so` output) does not exist anywhere
in `elfwriter.inc`** — confirmed by grep, zero hits. That's the one genuinely
net-new linker capability this ticket needs; the object/exe paths are mostly
wiring, not new machinery.

## Scope

- New lexer/parser pair for assembly syntax (own directives: `section`,
  `global`, `extern`, `align`, `db/dw/dd/dq`, labels) parsing into the same
  structured instruction-list IR [[feature-asm-structured-ir-library]]
  introduces — reuse, don't reinvent, the mnemonic table.
- Wire `.asm` into the existing source-dispatch path alongside `.pas`/`.c`
  (`compiler/parser.inc` extension-dispatch, same place `.c` was added).
- Object-file output: extend the existing `ET_REL` writer path if needed for
  asm-originated symbols (external refs via `extern`, exported via `global`).
- Executable output: reuse `ET_EXEC` writer as-is.
- **New:** `ET_DYN` shared-library writer — dynamic symbol table, `.dynsym`/
  `.dynstr`, `PT_DYNAMIC` segment, position-independent considerations. Cross-
  link with [[feature-real-dynlib-loader]] / [[feature-dynamic-soname-discovery]]
  if either already assumes or wants `.so` *production* (today they're
  consume-only: `DT_NEEDED` against system libs).

## Acceptance

- A hand-written `.asm` "hello world" / syscall-exit program assembles to a
  runnable `ET_EXEC`.
- `-c foo.asm` produces a valid `ET_REL` object, linkable by an external
  linker (and/or our own multi-object link path if one exists by then).
- `--shared foo.asm` produces a loadable `ET_DYN` `.so` (`dlopen` round-trip
  or equivalent smoke test).
- Round-trip with [[feature-asm-textual-emit-mode]]: reassembling a `.s` file
  the compiler emitted for a Pascal program reproduces byte-identical output
  to direct codegen, for at least one nontrivial test program.
- Self-host byte-identical; `make test` + cross green.

## Log
- 2026-06-30 — Opened (Track B, filing Track A-scope ticket per convention).
- 2026-06-30 — **labels + branches increment landed** (Track B+A) on top of the
  MVP: `compiler/asmfront.inc` now parses `name:` labels (alone or prefixing an
  instruction), `jmp`/`call`/`jcc <label>` rel32 branches (forward + backward,
  resolved post-parse via `Patch32`), `[base+disp]` memory operands, and real
  `syscall` — driven by the widened `lib/asmcore` x64 encoder + its patch-site
  contract. `test/test_asm_loop.asm` (cmp/jg loop) in `make test`. **Still
  deferred (the remaining scope of this ticket):** a data section + `db/dw/dd/dq`
  with rip-relative relocation, `section`/`global`/`extern` directives, `-c`
  `ET_REL` object output, `--shared` `ET_DYN` `.so` writer. Those give clear
  "not in this increment" errors today.
- 2026-06-30 — **data section + rip-relative `lea` landed** (Track B+A): `section
  .text`/`section .data` directives + `db/dw/dd/dq` (quote-aware, string
  literals only valid with `db`) feed a second byte buffer appended after
  code+epilogue (one contiguous `ET_EXEC` image); data-label offsets fold into
  the *same* label table code labels use, before fixup resolution runs.
  `lea reg, [rel label]` is the new operand form — `lib/asmcore/asmcore_x64.pas`
  grew a `REG_RIP = -2` sentinel (`MemOp(REG_RIP, 0)`) + `EncodeRegMemPatch`
  (ModRM mod=00/rm=101 + disp32 patch site, same opaque-patch-marker contract
  as branches), wired into the `mov reg,[mem]` and `lea reg,[mem]` two-operand
  arms. The frontend reuses the branch-fixup table verbatim for this — rip disp32
  and branch rel32 share the same `target - (patch_offset+4)` formula, so
  `[rel label]` just sets the same `branchLabel` var a `jmp <label>` would.
  `test/test_asm_hello.asm`: a real `write(1,msg,18); exit(0)` syscall program —
  first asm program that does I/O, not just arithmetic — in `make test`
  (`test-asm`, stdout-checked). LANDMINE: a local var named `low` collided with
  the compiler's reserved `Low` builtin token (case-insensitive) and broke
  self-host parsing with a baffling "expected (, but got" — renamed to
  `innerLower`. Self-host + threadsafe-self-host byte-identical, full `make
  test` green. **Still deferred:** `section`/`global`/`extern` symbol export,
  `-c` `ET_REL` object output, `--shared` `ET_DYN` `.so` writer, `mov
  [rel label], reg` (rip-relative store — only load/lea landed).
- 2026-06-30 — **User sequencing call:** heads 1 (inline `asm...end`) and 3
  (this `.asm` frontend) are primary now; head/layer-2 (migrating the
  compiler's *own* self-hosted codegen backends onto `lib/asmcore`, retiring
  the legacy emitters — see [[feature-asm-structured-ir-library]]) is
  deprioritized to "latest." Next legwork on this side: head 1, wiring
  `compiler/asmenc.inc`'s inline-asm parser to the existing structured engine
  per [[feature-asm-structured-ir-library]]'s corrected understanding (the
  per-target `EmitAsmXxx` engines already do labels/branches/relocations —
  this is parser-identifier-resolution wiring, not new encoder work).
- 2026-07-01 — **`extern`/`global` directives landed** (Track A), closing the
  last "not in this increment yet" gap short of `-c`/`--shared`:
  - `extern <name>[, "libname"]` (default `libc.so.6`) synthesizes a `Procs[]`
    entry exactly like a Pascal `external 'lib'` declaration
    (`ProcExternal`/`ProcLibrary`/`RegisterProc`), so `call <name>` reaches it
    through the **existing** dynamic-call machinery
    (`RegisterExternal`/`EmitExternalIndirectCall`, `PrepareDynamicData`/
    `PatchDynCallSites` in `elfwriter.inc`) unmodified — no new ELF-writer
    code needed for this part, exactly per the "current state of the linker
    backend" audit above. `jmp`/`jcc` to an extern name is rejected with a
    clear message (only `call`'s GOT-indirect form can reach it; a direct
    rel32 jump can't).
  - `global <label>`: overrides the ELF entry point (`entry := LOAD_ADDR +
    codeOffset` in both `writeELF` variants, `elfwriter.inc`) with a chosen
    code label's offset via a new `AsmEntryOff` global (`defs.inc`; always 0 —
    inert — for every non-`.asm` compile, so no other frontend is affected).
    First `global` naming an actual code label wins.
  - Verified for real: `test/test_asm_extern.asm` calls libc `printf` (+
    `fflush(NULL)` — see landmine below) via a hand-written `extern`
    declaration and prints through real dynamic linking, no hand-rolled
    syscall. `test/test_asm_entry_global.asm` proves `global` really
    redirects execution (two `SYS_exit` sites with different codes, not
    connected by any jump — only a working override reaches the second).
    Both in `make test` (`test-asm`).
  - **LANDMINE (real compiler bug, filed, not blocking):** a `var array[..] of
    AnsiString` parameter silently loses its element writes in the **pxx
    self-hosted** binary (works fine under a direct FPC build) — caught
    because a first-draft helper took the extern name/index table by `var`
    array param and the caller read back empty strings. Isolated to a minimal
    repro, `const` array-of-AnsiString reads confirmed fine, only `var`/write
    is broken. Worked around in `asmfront.inc` by having the helper return
    scalars (`var outName: AnsiString; var outProcIdx: Integer`) and letting
    the caller do the array write itself outside any array-typed parameter
    boundary. See `bug-var-array-of-ansistring-param-loses-writes.md` — a
    real, silent-data-corruption class of bug, left for Track A to pick up
    separately.
  - **Still deferred:** `-c` `ET_REL` object output, `--shared` `ET_DYN` `.so`
    writer (the one genuinely net-new linker capability per the audit above —
    `ET_DYN` doesn't exist anywhere in `elfwriter.inc` yet).
- 2026-07-01 — **`-c`/`--emit-obj` `ET_REL` object output landed** (Track A),
  new `writeELFRelX64` in `elfwriter.inc` — the x86-64 relocatable-object gap
  the earlier audit flagged (`writeELF32Rel` was xtensa/riscv32-only).
  - Design: everything the `.asm` frontend assembles — code, `section .data`
    bytes, even a data label's own bytes — lives in ONE combined `Code[]`
    blob (`asmfront.inc`'s existing "one contiguous loaded image" choice for
    `ET_EXEC`); the object writer keeps that and emits a single `.text`
    section covering the whole blob, so `global` symbols (code or
    `section .data` alike) all point into it — no separate `.data`/`.bss`
    section needed since there's no separate content. Internal `jmp`/`jcc`/
    `[rel]` references are already fully resolved by `ParseAsmProgram`
    (`Patch32`) before the writer runs, unchanged from `ET_EXEC` — the only
    thing that needs a *real* relocation is `call <extern>`.
  - `call <extern>` now branches on `EmitObjMode`: `-c` emits a plain `call
    rel32` placeholder (`E8` + 4-byte zero) instead of the GOT-indirect
    `ET_EXEC` form, recording `(code position, RegisterExternal index)` in
    new `AsmObjCallPos`/`AsmObjCallExtIdx` globals; `writeELFRelX64` turns
    each into an `R_X86_64_PLT32` relocation (addend `-4`, the same
    convention `gas`/`nasm` use for a `call` to an undefined symbol) against
    an `UND GLOBAL` symbol built from the *existing* `ExternalCount`/
    `ExternalProc[]` (`RegisterExternal` still dedups exactly like the
    `ET_EXEC` path). The auto-`SYS_exit` epilogue is skipped entirely in
    object mode — a `.asm` file compiled to an object is a reusable
    compilation unit for a real linker to combine, not a standalone process;
    forcing an exit syscall onto it would be dead code at best, actively
    wrong if it gets linked as a library.
  - `global <label>` widened from "remember one name" (the `ET_EXEC`-only
    entry-point override from the earlier increment) to a real list
    (`MAX_ASM_GLOBALS = 64`, `AsmGlobalSymName`/`Off`/`IsData` globals) — the
    *first* one naming a non-data label still overrides the `ET_EXEC` entry
    point (unchanged, existing tests still pass), and *every* one becomes an
    exported `GLOBAL` ELF symbol in object mode.
  - **Verified for real, not just structurally**: the resulting `.o` was
    linked with the *system* `ld`/`gcc` (not a hand-rolled linker) against
    real `libc.so.6` — `gcc -nostartfiles -e asm_obj_start file.o -o exe`
    runs and prints through a genuine `extern puts`/`fflush` `R_X86_64_PLT32`
    call; a separate C file (`extern int asm_obj_add(int,int);`) links
    against the same `.o` and calls the exported function correctly. Both
    checks now in `make test` (`test-asm`, gcc-guarded like the existing
    ESP `test-emit-obj` link checks) via `test/test_asm_obj.asm`. Self-hosted
    `compiler/pascal26`'s object output confirmed **byte-identical** to the
    FPC-built compiler's.
  - Structural checks (`readelf -h/-s/-r`) also in `make test`, same file.
  - Full `make test` green (backend/ELF-writer touch); self-host byte-
    identical bootstrap.
  - **Still deferred:** `--shared` `ET_DYN` `.so` writer (task #6 of the
    `full asm support for all 3 heads` umbrella) — the one remaining
    genuinely net-new linker capability.
