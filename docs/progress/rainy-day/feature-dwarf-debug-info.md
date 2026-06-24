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
