---
prio: 60  # auto
---

# `.asm` as a first-class source frontend (assemble + link to object/exe/.so)

- **Type:** feature (frontend / linker) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Relation:** part of [[feature-assembler-first-class-citizen]];
  consumes [[feature-asm-structured-ir-library]]; pairs with
  [[feature-asm-textual-emit-mode]] for round-trip validation.
- **Stale-ref note (2026-07-03):** [[feature-asm-structured-ir-library]]
  (the ir_codegen→asmcore emitter migration) was REJECTED by user decision —
  see that ticket's log and [[feedback_no_emitter_migration_asmcore]]. Its
  audit findings still stand as history/context; just don't treat it as a
  live blocking dependency.
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
- 2026-07-01 — **`--shared` `ET_DYN` shared-library output landed** (Track
  A), new `writeELFSharedX64` in `elfwriter.inc` — closes the last gap in
  the umbrella's acceptance criteria (`--shared foo.asm` produces a
  `dlopen`-loadable `.so`).
  - **No PIC codegen retrofit needed.** The `.asm` frontend's own addressing
    was already position-independent by construction going in: labels/
    branches are rip-relative, `[base+disp]` is register-relative,
    immediates are immediates — there is no absolute-address operand form
    in this frontend at all. The only thing that needed a genuinely new
    encoding was `call <extern>`, which gained a *third* form (alongside
    the ET_EXEC GOT-indirect-absolute and `-c` PLT32-relocation forms):
    `call qword ptr [rip+disp32]` (`FF 15`) — a rip-relative GOT access
    whose displacement is fixed at assemble time regardless of where the
    `.so` eventually loads (`AsmSoCallPos`/`AsmSoCallExtIdx`, resolved in
    `writeELFSharedX64` once the GOT region's address is known). The GOT
    slot itself is the *same* `ExternalGotOff[]`/`Data[]` allocation
    `RegisterExternal` already does for the `ET_EXEC` path — only filled by
    the dynamic linker's `R_X86_64_GLOB_DAT` relocation instead of by us.
    Net result: **zero `R_X86_64_RELATIVE` relocations needed** for this
    frontend's own code/data at any load address.
  - Preferred load base = 0 (vaddr == file offset throughout) — rip-relative
    code doesn't care what base the loader picks, so there was no reason to
    reserve a nonzero one.
  - **No section headers.** The dynamic linker resolves everything through
    `PT_DYNAMIC` and its `DT_SYMTAB`/`DT_STRTAB`/`DT_HASH` — confirmed by
    testing `nm -D`/`objdump -T` (which enumerate dynamic symbols via the
    hash table, no section headers needed) successfully against a
    section-header-less `.so`, matching how the `ET_EXEC` writer already
    omits them unless `-g`. Trade-off found empirically: **`ld`-time static
    linking against the `.so` fails** (`error adding symbols: file in wrong
    format`) — a real static linker's BFD-based symbol introspection wants
    section headers even though the runtime loader doesn't need them. The
    umbrella ticket's stated acceptance bar is "`dlopen` round-trip **or**
    equivalent smoke test" — `dlopen`/`dlsym` against the real system
    dynamic linker is fully verified (below), so this is a deliberate,
    documented scope boundary for this increment, not a gap in what was
    asked for. Full section-header support (`SHT_DYNSYM`/`SHT_STRTAB`/
    `SHT_HASH`/`SHT_RELA`/`SHT_DYNAMIC` cross-referenced correctly) would
    close it if `ld`-time linking against a `.asm`-built `.so` is ever
    wanted.
  - **Two real bugs found and fixed while building this** (both self-caught
    via byte-level inspection before landing, not left in):
    1. `.hash` table word-count miscounted by one word (4 bytes) —
       `hashSize` used `(dynCount+3)*4` where the actual write loop
       (`nbucket, nchain, bucket[0], chain[0..dynCount]`) emits
       `(dynCount+4)` words. Every offset computed *after* the hash table
       (`.rela.dyn`, the dynamic-entries block, `fileSize`) drifted by 4
       bytes from where the writer actually was in the file, corrupting
       every `Elf64_Dyn` entry (`readelf -d` showed tag values shifted into
       the wrong 32-bit half, e.g. `DT_NEEDED` reading as `0x100000000`
       instead of `0x1`). Caught by hex-dumping the dynamic section and
       comparing against hand-computed offsets — `readelf -d`'s own
       "offset" self-report wasn't enough to catch it, since that value
       just echoes back whatever the `PT_DYNAMIC` phdr says, not what's
       actually *at* that file position.
    2. The rip-relative GOT-call patch (`Patch32(AsmSoCallPos[i], target -
       (AsmSoCallPos[i]+4))`) used `AsmSoCallPos[i]` — a `Code[]`-internal,
       0-based offset (same coordinate space `CodeLen` always uses) — as if
       it were a full file/vaddr-relative position. It needed `textOff +
       AsmSoCallPos[i]` instead: the CPU's actual rip-relative arithmetic
       at runtime runs from the instruction's *true* address, not its
       offset within the compiler's internal `Code[]` buffer. Every
       internal `[rel label]`/branch fixup in this frontend was already
       immune to this class of bug by construction (both the label's
       recorded offset *and* the patch site's recorded offset live in the
       same `Code[]`-relative coordinate space, so `textOff` cancels out of
       the subtraction) — this was the *first* rip-relative reference in
       the frontend to point at something **outside** `Code[]` (the GOT
       slot, in the `Data[]`-equivalent region), which is exactly why the
       coordinate-space mismatch had never surfaced before. Caught by
       disassembling the actual patched call instruction, decoding its
       target by hand, and finding the diff from the correct target was
       exactly `textOff` (176 bytes) — not a coincidence once the two
       coordinate spaces were named.
  - **Verified for real**: `dlopen()`/`dlsym()` against the real system
    dynamic linker (glibc), not a hand-rolled loader — both a pure exported
    function (`so_add`, no relocations needed at all) and a function that
    calls libc through the new rip-relative GOT mechanism (`so_greet`,
    calling `puts`/`fflush`) resolve and execute correctly. `nm -D`/
    `objdump -T` independently confirm the dynamic symbol table (both
    tools enumerate symbols via `DT_HASH`, proving the hash table and
    `.dynsym`/`.dynstr` are genuinely well-formed, not just readable by
    `readelf -d`). Self-hosted `compiler/pascal26`'s `.so` output confirmed
    **byte-identical** to the FPC-built compiler's. `test/test_asm_so.asm`
    in `make test` (`test-asm`), gcc+dl-guarded like the `-c` object
    writer's link checks.
  - Full `make test` green; self-host bootstrap byte-identical.
  - **All three heads of `feature-assembler-first-class-citizen` now have a
    working increment** — head 3 (this ticket) covers `ET_EXEC`/`-c`/
    `--shared` for x86-64; remaining work across the umbrella: head 2
    (`-S` textual emit mode, x64 codegen — task #7 of the "full asm support
    for all 3 heads" session goal), plus the previously-scoped multi-target
    rollout (i386/aarch64/arm32/riscv32/xtensa) for this frontend, which
    stayed explicitly out of scope for this session ("land x86-64 first
    end-to-end... then the rollout to the other five is comparatively
    cheap" per the umbrella ticket).
- 2026-07-03 — **riscv32 leg landed** (Track A) — first target of the
  multi-target rollout. Cheap by design: unlike the x86-64 path (which
  predates the corrected understanding and drives lib/asmcore directly),
  ParseAsmProgramRv32 (asmfront.inc) feeds source lines straight through
  asmtext_rv32.inc's AsmRv32BlockBegin/ProcessLine/BlockResolve — the same
  block API inline `asm...end` replays through since
  [[feature-inline-asm-multi-arch]] — then the existing riscv32 ET_EXEC
  writer emits the image (writeELF32 gained `+ AsmEntryOff` for the
  `global <label>` entry override, inert 0 for every non-.asm compile).
  Scope this increment: instructions + labels + branches + `global` entry
  override + fall-through exit epilogue (exit code = a0, SYS_exit 93,
  mirroring x86-64's rdi contract). `section`/`extern`/db and
  `-c`/`--shared` give clear errors. test/test_asm_rv32_sum.asm (sum-loop
  exits 55; a pre-start exit-7 block proves the entry override actually
  redirects) in make test-riscv32. Also added
  test/test_asm_ifdef_multiarch.pas — one source, per-target inline-asm
  blocks behind {$ifdef CPUX86_64/CPURISCV32/CPUAARCH64} — wired into
  make test + test-riscv32 + test-aarch64 (documents the target-selection
  model: inline asm follows --target; portability = CPU-define guards).
  Remaining rollout: i386/aarch64/arm32 (same pattern), xtensa (blocked on
  the same engine gaps as [[feature-inline-asm-xtensa]]), and -c/--shared
  beyond x86-64.
- 2026-07-03 — **aarch64 + arm32 + i386 legs landed** (Track A): the rv32
  path generalized into ParseAsmProgramEngine (asmfront.inc), dispatching
  per target to the engines' shared BlockBegin/ProcessLine/BlockResolve
  API; per-ABI fall-through exit epilogues (rv32 a7=93/ecall exit=a0;
  aarch64 x8=93/svc exit=x0; arm32 r7=1/svc exit=r0; i386 eax=1/int 0x80
  exit=ebx). `svc` added to the a64 and arm32 engines — arm32's had to be
  matched BEFORE the condition-suffix stripper ('vc' is a valid cond code,
  so 'svc' was being mis-read as 's'+VC and rejected). Four sum-loop
  .asm tests (exit 55, pre-start exit-7 block proves the `global` entry
  override) wired into their cross suites. All engine-backed targets now
  parse .asm; xtensa gives a clear error pointing at
  [[feature-inline-asm-xtensa]]. Remaining scope: -c/--shared beyond
  x86-64, section/extern/db on the engine-backed targets.
