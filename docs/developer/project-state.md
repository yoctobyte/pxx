# Project State Audit

**Audited:** 2026-06-05

This is the compact current-state snapshot. Source and `make test` remain
authoritative. Detailed design notes live in [`todo.md`](todo.md), while older
point-in-time material stays under `historic/`.

## Architecture

- Pascal, C-subset, and BASIC-subset frontends share the native x86-64 Linux
  ELF emitter.
- Pascal and the covered C/BASIC paths lower AST to the linear IR in
  `compiler/ir.inc`, then emit machine code through `compiler/ir_codegen.inc`.
- The obsolete direct AST-to-x86-64 emitter was retired from the active build
  on 2026-05-31 and archived as
  `docs/historic/direct-codegen-legacy.inc`.
- `compiler/exception_emit.inc` contains the exception-runtime byte emitter
  shared by the active IR pipeline.
- `--experimental-ir-codegen` remains accepted as a deprecated no-op for old
  scripts. `--legacy-codegen` was removed.

## Verified Pascal Surface

`make test` covers procedural Pascal, units and initialization, arrays,
records, strings, classes, constructors, inheritance, `class of` metaclasses,
virtual/override and
abstract dispatch, visibility parsing, properties, published RTTI, reflection,
resources, LFM streaming, procedure/method pointers, integer and float
arithmetic, typed pointers, dynamic arrays of scalar values, opt-in managed
`AnsiString` arrays, exceptions,
generics, overloads, operators, qualified unit symbols, scaled typed-pointer
arithmetic, record/set aggregate-valued function results, conditional
directive expressions and active-branch includes, inline asm, `goto`, `with`,
comments, case modes, allocator builtins,
`read`/`readln`, and selected RTL helpers.

Case behavior is per origin:

- Pascal declarations are case-insensitive by default.
- `{$CASESENSITIVE ON}` enables strict Pascal declaration matching.
- C imports remain exact-case because emitted ELF link names are exact.

## Confirmed Bugs

- None. (The hang compiling `test/test_basic_lexer.bas` was resolved on 2026-06-01 by adding Block IF support to the BASIC parser).

## Latest Benchmark Snapshot

The post-gate 2026-06-02 `make benchmark` run is recorded in
[`benchmarks/2026-06-02-runtime-gate.md`](../benchmarks/2026-06-02-runtime-gate.md). On
the recorded host, the self-hosted compiler remains 1.12x faster than FPC when
compiling its expanded source tree and 18.80x faster for a batch of twenty
Pascal hello-world compiles. The directly emitted static hello-world ELF is
back to 287 bytes.

## Latest Runtime Progress

### 2026-06-05 — default keyword and managed self-compile fixedpoint

- `default` assignment is implemented and covered by
  `test/test_default_keyword.pas`: scalar and pointer targets reset to zero,
  string targets reset to empty, and managed record storage is cleared through
  the assignment path.
- The opt-in managed `AnsiString` compiler build now reaches byte-identical
  fixedpoint through the committed managed bootstrap targets. The earlier
  stage-2 CPU/RSS growth blocker is gone; the remaining question is when and
  how to promote the managed ABI from opt-in to default.

### 2026-06-04 — generic collection library

A single generic `TList<T>` template (`lib/rtl/collections.pas`) now backs a
duplication-free collection library, specialized per element type from any
program. This closed three layers in one arc:

- **Managed dynamic-array fields.** `array of T` is now a first-class managed
  field of a record or class — `SetLength`, `Length`, indexed read/write,
  copy-on-write, retain-on-copy, and scope-exit finalization all operate on the
  field slot, not only a top-level local. Field-target `SetLength` carries
  element metadata on the IR node (symIdx=-1) so the symbol path stays
  byte-identical. (`test/test_dynarray_field.pas`.)
- **Instance zero-fill.** Class instances are zeroed on construction, so a
  freshly `Create`d managed field starts `nil` even when its backing block is a
  reused free-list block — without this the field `SetLength` dereferenced
  stale data and faulted.
- **Generic classes, including cross-unit.** `generic TFoo<T> = class ... end;`
  plus `specialize` now actually work (the wired-but-broken path had three
  token-stream bugs). A template can live in a used unit and be specialized
  from the program; method bodies are materialized at the specialization site,
  deferred past the type section so multiple specializations compose.
  (`test/test_generic_func.pas`, `test/test_collections.pas`.)

`TList<T>` is the deliverable these enabled: managed dynarray storage, chunked
(doubling) growth, no manual allocation or freeing, one template for both
scalar `Integer` and managed `AnsiString` elements.

### 2026-06-02 — managed dynamic-array runtime

The 2026-06-02 managed-runtime batch established generic dynamic-array
copy-on-write and the first managed-element slice:

- Dynamic-array locals are initialized to `nil`.
- Assignment retains the new allocation and releases replaced storage.
- Indexed writes clone shared dynamic-array storage before mutation.
- `SetLength` preserves the retained prefix when growing or shrinking, zeroes
  newly exposed scalar slots, and releases storage for `SetLength(a, 0)`.
- Replaced blocks return to the existing free list.
- Refcount increments/decrements are ordinary instructions by default and gain
  an atomic prefix only with `--threadsafe` / `{$THREADSAFE ON}`.
- Dynamic-array locals release storage on normal procedure exit.
- Under `{$define PXX_MANAGED_STRING}`, `array of AnsiString` retains copied
  element references during clone/resize and releases elements when the final
  array owner dies.
- `test/test_dynarray.pas` covers scalar preservation, zeroing, alias
  assignment, copy-on-write, and copy-on-resize.
  `test/test_dynarray_ansistring.pas` covers managed-element aliasing, resize,
  shrink, cleanup, and threaded emission. `test/test_multithreading.pas`
  repeatedly resizes local arrays while four pthread workers allocate and free
  raw heap blocks.

Verification passed after the batch:

```text
make all
make test
thread-safe managed-string dynamic-array regression
git diff --check
```

The allocator direction is now fixed in
[`allocator-platform-design.md`](allocator-platform-design.md): managed values
must call a target-neutral `Alloc` / `Free` / `Realloc` contract. Every target
gets a syscall-free internal heap. Linux `mmap`/`munmap`, ESP32 linker-defined
RAM regions, and possible ESP32 RTOS services are target hooks, not language
runtime dependencies.

## Major Missing Pascal Features

- Interfaces are intentionally deferred until a concrete compatibility target
  needs them; see `todo.md` section 3.
- Metaclass aliases are pointer-backed and do not yet enforce every descendant
  constraint against arbitrary pointer-compatible assignments.
- Float conversion intrinsics such as `Trunc`, `Round`, `Int`, and float
  `Str`/`Val`.
- Managed `AnsiString` is available as an opt-in
  `{$define PXX_MANAGED_STRING}` slice: heap-backed refcounting, normal local
  cleanup, copy-on-write indexed writes, concatenation, coercions,
  `SetLength`, params/results, argument temporaries, dynamic-array elements,
  records with managed fields, and managed compiler self-compile fixedpoint.
  The default representation remains inline while globals, exception
  unwinding, and final default-ABI promotion are decided.
- Dynamic arrays support scalar elements, opt-in managed `AnsiString`
  elements, records recursively containing managed strings, and nested arrays
  of those bases at any depth. Assignment,
  indexed-write copy-on-write, preserving resize, zero-initialized growth,
  replacement reclaim, normal local cleanup, nested-level copy-on-write,
  fresh-result move semantics, argument-temp ownership, and conditional atomic
  refcounts are covered. Deferred semantics: exception-path cleanup.
- Full access-control enforcement is intentionally deferred. Visibility
  sections are parsed because `published` drives RTTI; rejecting
  private/protected access enables no new programs.
- FPC directive breadth beyond the covered expression subset: checking,
  optimization, and code-generation switch state.
- Broader unit namespace/import behavior beyond qualified `UnitName.Symbol`
  resolution, such as a possible nonstandard rename-import extension.

## Broader Design Debt

- Active compiler internals are still one include-heavy translation unit.
- Built-in compiler record layouts in `symtab.inc` are now computed from
  metadata tables and validated against the frozen ABI. Extending those records
  still requires synchronized metadata updates, but the old hand-derived
  `RecSize`/`RecFieldOffset` chains are gone.
- The allocator uses a simple first-fit free list with no splitting,
  coalescing, bins, or in-place resize. Linux arena growth currently emits
  `mmap` directly; the next allocator refactor must move that behind optional
  platform hooks and provide a syscall-free internal heap for embedded targets.
  See [`allocator-platform-design.md`](allocator-platform-design.md).
- There are no IR optimization passes, register allocation, or additional CPU
  targets.
- Pascal now uses a conservative token-reachability gate to omit unused heap
  startup and managed-string helpers. Plain hello is back to 287 bytes.
  Helper-level splitting and argv-stack gating remain optional code-size
  cleanup, not architectural blockers for embedded targets; see
  [`runtime-emission-size-audit-2026-06-02.md`](runtime-emission-size-audit-2026-06-02.md).
- The C importer has advanced (2026-06-01, see `plan-c-header-import.md`): real
  C type model (widths/signedness/void/pointers), typedef + enum + opaque
  struct/union resolution, the full SysV float and >6/>8-arg stack-spill call
  ABI, and DT_NEEDED dedup with a versioned soname table. Still needed before
  real GTK/glib headers replace handwritten bindings: macro-soup preprocessing
  (token paste/stringify/variadic/attributes), struct field layout, callback
  signatures, and a dynamic soname probe.
- SQLite is driven end-to-end from the imported `/usr/include/sqlite3.h`
  (2026-06-02): open/exec/prepare/step plus `column_int`/`column_text`, linked
  against `libsqlite3.so.0`. Added to support it: C function-pointer params map
  to `Pointer` (were leaking the base `int`), `PChar()` marshals a Pascal string
  to a `const char*` (literal interner now NUL-terminates), and `PChar` is a
  usable/indexable pointer type. Regression `test/test_sqlite_crud.pas`.
- Imported C parameter pointer depth is recorded separately from the Pascal
  surface type. This supports strict Nil Python trailing `T**` out-param
  return-lifting while keeping depth-1 `T*` as a normal pointer argument.
- Nil Python (`.npy`) gained `import name` (2026-06-02), routed to the same
  unit/C-header resolver as Pascal `uses`. It imports C headers directly
  (`import sqlite3` → `sqlite3_libversion_number()`), and now drives full SQLite
  CRUD directly from the imported header: lifted `sqlite3_open` /
  `sqlite3_prepare_v2`, direct `sqlite3_exec` / `step` / `column_int`, and
  copied `char*`→managed-string for `column_text`. (A `sqlitedb.pas` facade was
  removed 2026-06-06 — the direct path needs no wrapper.)
  Regressions `test/test_nilpy_import_sqlite.npy`,
  `test/test_nilpy_sqlite_crud.npy`. Python `print` now space-separates args.
- Automated GUI tests remain separate because they require GTK/display
  environment handling.

## Ordered Next Work

1. Introduce central target-neutral allocator helpers and route raw memory,
   classes, dynamic arrays, and later managed strings through them. Memory
   management is a per-target/per-frontend **profile** sharing this contract
   (ARC default · arena embedded · hosted conservative+cycle collector); GC is
   never the default — see
   [`garbage-collection-thoughts.md`](garbage-collection-thoughts.md).
2. Add a fixed-static-arena profile that proves allocator and managed-value
   tests pass without `mmap`, `munmap`, or `brk`.
3. Implement allocator splitting, coalescing, alignment, and in-place
   `Realloc` attempts; keep hosted and RTOS facilities behind optional hooks.
4. Decide how to package or promote the opt-in managed `AnsiString` ABI now
   that managed self-compile fixedpoint is reached; keep global managed payload
   cleanup, exception-path cleanup, and record/class ownership audits visible.
5. Finish remaining managed-value ownership paths that still affect uncovered
   aggregates and exceptional exits.
6. Audit threaded compound runtime operations: statement-level
   `write`/`writeln`, shared `read`/`readln` state, and exception globals.
