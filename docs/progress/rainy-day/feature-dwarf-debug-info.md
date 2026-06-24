# DWARF debug info (`-g`) — phased, x86-64 first

- **Type:** feature
- **Status:** rainy-day 
- **Owner:** —
- **Opened:** 2026-06-20 (feasibility discussion — debugger support)
- **Priority:** high value, but after the current correctness/breadth arc. Pairs
  with [feature-optimization-levels](feature-optimization-levels.md): `-O0`'s
  1:1 source↔asm contract is what makes debug info accurate.

## Motivation

PXX emits **no debug info of any kind** today — no `.debug_*`, no stabs. A PXX
binary is opaque to gdb/lldb: no line numbers, no function names in backtraces,
no variable inspection. As programs (and the compiler itself) grow, the absence
of a real debugger is the main productivity gap. Target **DWARF** (debug
DWARF3 as the nominal version; gdb consumes 2/3/4/5 and the line program barely
differs across them).

## Key feasibility fact: PXX is its own linker

PXX writes the **final ET_EXEC directly** (own program headers, own dynamic
tables, picks the `ld.so` interpreter itself — `elfwriter.inc`). There is no GNU
`as`/`ld` in the final path. Therefore **nothing downstream can emit DWARF for
us — PXX must write every `.debug_*` section byte-by-byte.** Full burden, but
full control and zero new toolchain dependency. The section-emission machinery
(shstrtab, section headers, symtab) already exists in `elfwriter.inc` to extend.

## Current state (examined 2026-06-20)

- Tokens carry `.Line` (`CurTok.Line`, `Tokens[].Line`). That is the only
  source-location data that survives lexing.
- AST nodes are **parallel arrays** (`ASTKind`/`ASTLeft`/`ASTIVal`/`ASTTk`/…) —
  **no `ASTLine`**. IR instructions carry **no line** either. So source→address
  mapping requires new plumbing lexer→AST→IR→emit.
- `Procs[].BodyAddr` already records each function's code offset — the anchor for
  per-function PC ranges and the line program.

## Plan — three burden tiers, ship as separate sub-tickets

### Tier 1 — `.debug_line` (address → file:line). Highest value/effort ratio.
Delivers gdb breakpoints, single-step, `Ctrl-C`-shows-location, and line numbers
in backtraces. **This tier alone = a usable debugger.**
- Add `ASTLine[]` parallel array; set from `CurTok.Line` at every AST-node alloc.
  (Parallel array, **not** a TSymbol field — dodges the MAX_UFIELD overflow
  landmine; but every node-alloc site must set it, same discipline as the
  symtab `Alloc*` parallel-array landmine.)
- Add `IRLine[]` parallel array; propagate AST line → IR at build.
- At emit, collect `(code offset, line, file)` rows.
- Emit the `.debug_line` state-machine program (version-agnostic enough across
  DWARF 2..5).

### Tier 2 — `.debug_info` + `.debug_abbrev` + `.debug_str`: subprograms.
DIEs for the compile unit + one `DW_TAG_subprogram` per function (name,
`low_pc`/`high_pc` from `Procs[].BodyAddr`, frame-base). → function names in
`bt`, proper frames. No type system needed yet.

### Tier 3 — locals / params / types. The long tail, incremental.
`DW_TAG_variable` / `DW_TAG_formal_parameter` with location expressions
(frame-base + slot offset), and the type DIE graph mapping the `tyXxx` model +
records/classes/dynarrays/managed strings/variants to
`DW_TAG_base_type`/`pointer_type`/`structure_type`/`array_type`. Enables
`print x` and struct inspection. Largest piece; land type kinds one at a time.

## Cross-target (×5, deferred until x86-64 proven)

DWARF content is target-independent **except**: PC/address values, the
frame-base register (rbp / x29 / r11 / …) via the per-ABI DWARF register-number
map, and pointer width (DWARF32 form on the ELF32 targets i386/arm32/riscv32/
xtensa). One emitter + a small per-arch register/width table. Do x86-64 end to
end first; generalise after.

## Gates / interactions

- **`-g` is opt-in, OFF by default.** Self-host and `make bootstrap`/
  `cross-bootstrap` emit no debug sections → **byte-identical path unaffected.**
- **Determinism.** DWARF bytes derive only from stable source/line/type data, no
  addresses-as-keys or map iteration order → emission is deterministic. (A `-g`
  self-host could even stay byte-identical if ever wanted.)
- **Optimizer interaction.** `-O0` keeps the 1:1 source↔asm contract → clean
  stepping. `-g -O2` degrades line/var fidelity (same as GCC); acceptable, do
  not promise accurate optimized-build debug in v1. See
  [feature-optimization-levels](feature-optimization-levels.md).

## Build-out order (split when work starts; do not pre-flood the board)

1. Tier 1 `.debug_line`, **x86-64 only** — prove gdb steps a PXX binary,
   breakpoints hit, `bt` shows lines.
2. Tier 2 subprograms (function names / frames).
3. Tier 3 locals + base types, then aggregate types incrementally.
4. Cross-target generalisation.

## Acceptance

- **Tier 1:** `pxx -g hello.pas` → gdb sets a line breakpoint that hits,
  `step`/`next` track source lines, `bt` shows file:line. `make test` green;
  default (no `-g`) output and `make bootstrap` byte-identical unchanged.
- **Tier 2:** `bt` shows PXX function names with correct frames.
- **Tier 3:** `print <local>` yields correct values for base types; struct/record
  fields inspectable.
- Cross-target: same gdb behaviour on i386 + aarch64 + arm32 (under QEMU);
  `make cross-bootstrap` byte-identical unaffected (debug off on the self-host
  path).

## Related

- [feature-optimization-levels](feature-optimization-levels.md) — `-O0` 1:1
  contract underpins accurate debug; the two arcs are composable.
- [feature-compiler-warnings](feature-compiler-warnings.md) — adjacent
  developer-experience work.

## Re-validation 2026-06-24 (all claims still hold) + plan refinements

Code re-checked against current tree. Findings that change the estimate:

- **Line capture is ~3 sites, not 540.** `AllocNode` (parser.inc:13) and
  `IRAppend` (ir.inc:21) are each a single definition. Capture `CurTok.Line`
  *inside* `AllocNode` → `ASTLine[]`; set a `CurLowerLine` global at the top of
  `IRLowerAST` (= `ASTLine[node]`); read it in `IRAppend` → `IRLine[]`. No need
  to touch the 540 call sites.
- **Emit hook is clean.** `IREmitNode` (ir_codegen.inc:1391, x64) — `CodeLen` at
  entry is the address where that node's code begins → push a
  `(CodeLen, IRLine[node])` row when the line changes. One backend for Tier 1.
- **`writeELF` has NO section-header table** (elfwriter.inc:646; e_shoff=0). gdb
  reads `.debug_*` via section headers, so the `-g` exe path must ADD a section
  header table + `.shstrtab`. The byte-writers exist (`writeShdrA/B`,
  `writeStrZ`) — used today only in the ET_REL (`--emit-obj`) and ESP paths — so
  it is wiring, not new machinery. ~80 lines, gated on `-g`.
- **Tier 1 also needs a minimal `.debug_info` CU stub.** A `.debug_line` table is
  only usable when a CU DIE references it via `DW_AT_stmt_list`. So Tier 1 ships
  with a one-DIE `.debug_info` + `.debug_abbrev` + `.debug_str` (CU name /
  comp_dir / stmt_list, ~40 bytes). (Ticket had this under Tier 2; it rides with
  Tier 1 in practice.)

### Graceful-degradation decision (kills the Tier-3 bulk)

Anything with runtime/heap layout is emitted as a **labeled
`DW_TAG_pointer_type`**, NOT a byte-exact ABI struct DIE:
- dynarray `array of T` → pointer named `"array of <T>"` (gdb shows handle;
  `print p^` if pointee set).
- managed string / AnsiString → pointer named `"string"` (gdb `x/s` works — data
  is NUL-terminated — no struct DIE needed).
- variant → opaque pointer. class instance → pointer to the struct DIE.

What stays "real" (all cheap, RTTI-backed): base types (`DW_TAG_base_type`),
records/classes (`DW_TAG_structure_type` + members from the EXISTING RTTI:
`__rttireg` / `UClsRTTIOff` / typinfo — do NOT rebuild field metadata), fixed
arrays (`DW_TAG_array_type`). The expensive part — describing dynarray/string/
variant runtime layout byte-exact — is DELETED. Inspection works for ints,
records, class fields, fixed arrays; the hard 10% shows a labeled pointer
instead of nothing.

Refined effort: Tier 1 (line + CU stub) ≈ 1 session; Tier 2 (subprograms/frames)
small; Tier 3-lite (base types + RTTI structs + pointer-cheat) ≈ 1 session.

## Log
- 2026-06-20 — ticket opened from DWARF feasibility examination. Findings: no
  debug info exists; PXX is its own linker so must emit all `.debug_*` itself;
  line info dies at the lexer (tokens have `.Line`, AST/IR do not). Plan: three
  tiers (`.debug_line` → subprograms → locals/types), x86-64 first, `-g`
  opt-in so self-host byte-identical is untouched.
- 2026-06-24 — re-validated against current tree (claims hold); added line-capture
  / emit-hook / section-header findings + the pointer-cheat degradation decision
  (see section above). Tier 1 confirmed ~1-session feasible.
- 2026-06-24 — **Tier 1 LANDED (x86-64, `-g` opt-in).** `pxx -g hello.pas` now
  emits `.debug_line` + a minimal CU stub; gdb resolves+hits a line breakpoint,
  `step`/`next` track source lines, frame 0 of `bt` shows `file:line`. (`bt`
  function NAMES are still `??` — that is Tier 2 subprograms, as designed.)
  Implementation as planned:
  - `ASTLine[]` set in `AllocNode` (parser.inc) from `CurTok.Line`, but ONLY for
    main-file nodes (`TokPos <= DbgMainTokEnd`) — appended builtin/RTL units lex
    with their SrcLine reset to 1 per unit (LexAppend), so without this guard
    their rows collide with the user file's lines under the single shared file
    entry. `DbgMainTokEnd` is set to `TokCount` right after `LexAll`.
  - `CurLowerLine` global tracked at the top of `IRLowerAST`; `IRLine[]` stamped
    in `IRAppend`.
  - Row collection in the x64 `IREmitMachineCode` loop (`CodeLen` at the start of
    each statement whose line changed). `DwarfLastLine` reset per proc.
  - All `.debug_*` bytes built into one `DbgBuf` (BuildDwarfSections in
    elfwriter.inc): `.debug_line` (DWARF3 state machine), `.debug_abbrev`,
    `.debug_info` (one compile_unit DIE, inline `DW_FORM_string` — NO `.debug_str`
    needed), `.shstrtab`. Both `writeELF` variants (FPC seed + self-host) gained a
    `-g`-gated section-header table (`writeShdr64`, Elf64_Shdr) + `e_shoff`/
    `e_shnum=5`/`e_shstrndx=4`. Debug sections live past `p_filesz` (unmapped).
  - `-g` flag in compiler.pas; `DebugInfo` global, default False.
  - Gates: `make test` green; self-host + cross-bootstrap byte-identical
    (the row-recording is behind `if DebugInfo`, so `-g`-off codegen bytes are
    unchanged → no reseed). New `make test-debug-g` (tools/dwarf_smoke.sh):
    readelf decodedline rows + gdb break/run/bt.
  LANDMINES recorded: (1) SLEB128 needs a real arithmetic shift — Pascal `div`
  truncates toward zero and `shr` is logical; bias `(v-127) div 128` for negatives.
  (2) per-unit SrcLine reset means a one-file line table MUST filter to main-file
  tokens or every unit's "line N" aliases the user's "line N".
  Next: Tier 2 (subprograms → real `bt` names/frames), then Tier 3-lite.
- 2026-06-24 — **Tier 2 + Tier 3-lite LANDED (x86-64, `-g`).** `bt` now shows PXX
  function names + file:line frames; `print`/`info args` read params, locals, and
  globals; records inspect field-by-field (`print p` → `{x = 3, y = 4}`); strings
  read via `x/s`. All behind `if DebugInfo` → self-host + cross-bootstrap stay
  byte-identical (verified). New `make test-debug-g` now asserts the Tier 2/3
  behaviour too.
  Implementation:
  - **Side tables, not live symtab.** Symbol slots recycle across procs (SymCount
    restored at each proc end), so params/locals are GONE by writeELF time. Capture
    them during compile: `DbgCaptureProcLocals` (parser.inc, before scope teardown)
    snapshots `Syms[ScopeBase..SymCount-1]` into the `DbgVar*` arrays; program
    globals captured at ParseProgram end (skGlobal past `DbgGlobalScopeBase`).
    `ProcDbgMain[]` flags main-file procs; `DbgMainBodyStart/End` + `DbgProgName`
    bound the program body.
  - **.debug_info DIEs** (BuildDwarfSections, elfwriter.inc): CU(children) →
    type DIEs first (so param/var `ref4`s point backward) → one `DW_TAG_subprogram`
    per main-file proc + one for the program body (name, low/high_pc from
    `Procs[].BodyAddr`/`ProcBodyEnd`, `frame_base = DW_OP_reg6`), each with its
    captured `formal_parameter`/`variable` children. Locations: globals
    `DW_OP_addr`(bssBase+off); locals/params `DW_OP_fbreg`(off), +`DW_OP_deref`
    for by-ref params.
  - **Types** (graceful degradation): base types → `DW_TAG_base_type`; records →
    `DW_TAG_structure_type` with members from the EXISTING UFld* tables (no field
    metadata rebuild); fixed arrays → `array_type`+`subrange`; class/string/
    pointer/variant/dynarray → labeled `DW_TAG_pointer_type` (the pointer-cheat).
    Deduped via the `(cat,recId,aux)` map.
  - **Allocated sections required.** Two new LANDMINES that cost real debugging:
    (a) gdb segfaults when a `DW_TAG_subprogram`'s `low_pc` lands in NO allocated
    section — the `-g` ELF MUST carry real `.text`/`.data`/`.bss` section headers
    (sh_addr set), not only `.debug_*`. `find_pc_section` returns null otherwise.
    (b) `break <func>` only skips the prologue cleanly when a line row exists AT
    the function's `low_pc`; without it gdb's arch analyzer stops mid-prologue
    (before params are stored → args read as 0). Fix: emit an entry row at
    `Procs[].BodyAddr` plus `DW_LNS_set_prologue_end` on the first body row.
  - Helpers split to ≤6 params (`writeShdr64` + per-call `DbgShFlags/Addr/Align`
    globals) to dodge the many-param-call-corruption backend landmine.
- 2026-06-24 — **CFI (`.debug_frame`) + cheat-label polish LANDED (x86-64).**
  Native x86-64 debug is now feature-complete; only cross-target remains.
  - **`.debug_frame`** (DbgEmitFrame): one CIE (standard rbp frame: `def_cfa
    rsp+8`, `RA@cfa-8`, data_align -8, RA reg 16) + one FDE per main-file proc
    (`advance_loc 1; def_cfa_offset 16; offset rbp@cfa-16; advance_loc 3;
    def_cfa_register rbp` — byte offsets MUST match the emitted `push rbp`(1)/
    `mov rbp,rsp`(3)) + a program-body FDE with `DW_CFA_undefined RA` so the
    unwinder terminates. Result: robust unwinding everywhere (incl. a clean
    SIGSEGV backtrace — `bt` shows the faulting frame, args like `p=0x0`, the
    whole call chain, and stops at the program body) and the junk outermost
    frame is GONE. Chose `.debug_frame` over `.eh_frame` (absolute addresses,
    rides the existing unmapped-debug-section machinery; CIE_id = 0xFFFFFFFF).
  - **Cheat labels**: runtime-layout types now emit a `DW_TAG_typedef` over a
    shared anonymous void pointer, so gdb shows the real Pascal name (`whatis s`
    → `string`, `whatis arr` → `array of Integer`) instead of `^pointer`, while
    `x/s`/handle inspection still work.
  - New `make test-debug-g` assertions: no junk `?? ()` frame, and a SIGSEGV
    sample unwinds to the named faulting frame at `file:line`.
  All behind `if DebugInfo` → self-host + cross-bootstrap byte-identical (verified).
  LANDMINE added: `.debug_frame` FDE prologue offsets are hard-coded to the
  standard `push rbp; mov rbp,rsp` byte lengths — asm-body procs and any future
  prologue change would desync the CFI (generators are fine, they still go
  through EmitProcPrologue).

  Remaining (deferred): pointer-cheat element inspection (`print arr[i]`/struct
  string DIE — the byte-exact ABI struct the ticket deleted; do not rebuild
  unless a workflow needs it); class instances still show as a labeled pointer
  rather than a pointer-to-its-structure_type; **cross-target generalisation
  (×4: i386/aarch64/arm32 + ELF32 section-header table in `writeELF32`, per-arch
  DWARF reg map, DWARF32 addr width)** is the only big piece left. Tier 1-3 +
  CFI complete for x86-64.
