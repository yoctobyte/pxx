---
track: A
tags: [C]
prio: 20
type: feature
blocked-by: []
summary: "C file-scope initialisers can now be laid out as .data with relocations instead of stores run before main (Gibux item 1). It is on under --freestanding, where an initialiser it cannot place is an error naming the global, and opt-in for executables with --c-static-data (PXXDBG=c.staticdata forces it, for corpus runs). x86-64 only. Covers integer constant expressions, floats, bit-fields, strings, string/function/global addresses (incl. &g.field and &a[i]) and designated struct/array initialisers. __attribute__((aligned(N))) on a global is honoured on the way."
status: done
owner: unassigned
---

# C file-scope initialisers become static data

pxx kept every C global in .bss and assigned its initial value in an init
thunk (PendingInit / CAggInit, replayed by CompilePendingGlobalInits). A
kernel has nothing to run a .init_array, so `--emit-obj --freestanding`
refused 8 of the Gibux kernel's files.

## How it works

- `CStaticDataMode` (set by `--freestanding` and `--c-static-data`): when a
  C global has an initialiser, `CPlaceGlobalInData` (symtab.inc) moves it to
  the data image at `DATA_SYM_BIAS + offset`, zero-filled. It refuses if code
  already references the global's old slot (a GlobFix exists), and refuses an
  alignment above 16 in an executable, whose RO split keeps alignment only
  mod 16.
- The init-store sites (CEmitDeferredCAggInits, CInitEmitAssign,
  CompilePendingGlobalInits) first try `CTryBakeGlobalInit` (ir.inc). It
  evaluates the AST of each store into bytes in the data image. Addresses
  become entries in a new relocation table (CDR*: kind DATA / PROC / SYM,
  target, addend). If the bake succeeds the store is not emitted.
- The executable writer applies CDR entries in ApplyImageFixups. The object
  writer emits them as R_X86_64_64 relas against .data, the procedure's
  symbol, or an import. Data-resident globals get their symbols in .data
  (shndx 3). CDR_PROC targets are DCE roots.
- Under --freestanding a store that cannot be baked is an error:
  "C global X: its initialiser is not a constant this compiler can place in
  .data (AST node kind N ...)".

## Test

test/c_file_scope_initialisers_are_data.c, with .expected from gcc. Each row
compares against gcc's output:

- plain (run-time stores);
- `--c-static-data`;
- `--emit-obj --freestanding`, linked by `gcc -no-pie`, so the relocations
  are what is tested.

The d9a0d9a599 compiler refuses the freestanding compile ("needs run-time
initialisation").

All 30 Gibux kernel C files (kernel e8ea914) now compile with
`--emit-obj --freestanding`.

## Found on the way

- [[bug-c-aligned-on-a-global-variable-is-ignored]] (fixed here).
- [[bug-c-a-block-scope-extern-with-no-file-scope-declaration-is-undeclared]]
  (fixed here).
- [[bug-c-a-file-scope-constant-right-shift-of-a-negative-value-is-logical]]
  (filed; it predates this change).
