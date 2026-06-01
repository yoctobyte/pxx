# Project State Audit

**Audited:** 2026-06-01

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
arithmetic, typed pointers, dynamic arrays of scalar values, exceptions,
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

## Latest Runtime Progress

The 2026-06-01 managed-runtime batch established the scalar dynamic-array
baseline:

- Dynamic-array locals are initialized to `nil`.
- Assignment retains the new allocation and releases replaced storage.
- `SetLength` preserves the retained prefix when growing or shrinking, zeroes
  newly exposed scalar slots, and releases storage for `SetLength(a, 0)`.
- Replaced blocks return to the existing free list.
- Refcount increments/decrements are ordinary instructions by default and gain
  an atomic prefix only with `--threadsafe` / `{$THREADSAFE ON}`.
- `test/test_dynarray.pas` covers preservation, zeroing, alias assignment, and
  copy-on-resize. `test/test_multithreading.pas` repeatedly resizes local arrays
  while four pthread workers allocate and free raw heap blocks.

Verification passed after the batch:

```text
make all
make test
thread-safe dynamic-array aliasing regression
10 repeated pthread resize stress runs
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
- Managed `AnsiString`: current strings are inline fixed-capacity values. The
  target ABI is now fixed: heap-backed, reference-counted, copy-on-write
  strings with a trailing zero byte for `PChar` compatibility. The value ABI
  stays identical in both modes; refcount updates become atomic only with
  `--threadsafe` / `{$THREADSAFE ON}`. See
  [`threads-todo.md`](threads-todo.md).
- Dynamic arrays support scalar elements, assignment retain/release,
  preserving resize, zero-initialized growth, replacement reclaim, and
  conditional atomic refcounts. Still missing: automatic scope-exit release,
  record or string elements, and params/results. Deepen these after allocator
  and managed-`AnsiString` work.
- Full access-control enforcement is intentionally deferred. Visibility
  sections are parsed because `published` drives RTTI; rejecting
  private/protected access enables no new programs.
- FPC directive breadth beyond the covered expression subset: checking,
  optimization, and code-generation switch state.
- Broader unit namespace/import behavior beyond qualified `UnitName.Symbol`
  resolution, such as a possible nonstandard rename-import extension.

## Broader Design Debt

- Active compiler internals are still one include-heavy translation unit.
- Several compiler record layouts are hardcoded in `symtab.inc`; extending
  those records requires synchronized metadata changes and often an FPC
  bootstrap.
- The allocator uses a simple first-fit free list with no splitting,
  coalescing, bins, or in-place resize. Linux arena growth currently emits
  `mmap` directly; the next allocator refactor must move that behind optional
  platform hooks and provide a syscall-free internal heap for embedded targets.
  See [`allocator-platform-design.md`](allocator-platform-design.md).
- There are no IR optimization passes, register allocation, or additional CPU
  targets.
- The C importer has advanced (2026-06-01, see `plan-c-header-import.md`): real
  C type model (widths/signedness/void/pointers), typedef + enum + opaque
  struct/union resolution, the full SysV float and >6/>8-arg stack-spill call
  ABI, and DT_NEEDED dedup with a versioned soname table. Still needed before
  real GTK/glib headers replace handwritten bindings: macro-soup preprocessing
  (token paste/stringify/variadic/attributes), struct field layout, callback
  signatures, and a dynamic soname probe.
- Automated GUI tests remain separate because they require GTK/display
  environment handling.

## Ordered Next Work

1. Introduce central target-neutral allocator helpers and route raw memory,
   classes, dynamic arrays, and later managed strings through them.
2. Add a fixed-static-arena profile that proves allocator and managed-value
   tests pass without `mmap`, `munmap`, or `brk`.
3. Implement allocator splitting, coalescing, alignment, and in-place
   `Realloc` attempts; keep hosted and RTOS facilities behind optional hooks.
4. Implement managed `AnsiString`: pointer slot, refcount, capacity,
   copy-on-write, and a trailing `#0` byte for direct `PChar` compatibility.
5. Add general managed-value finalization, then complete dynamic arrays:
   scope-exit release, params/results, arrays of strings, and arrays of records.
6. Audit threaded compound runtime operations: statement-level
   `write`/`writeln`, shared `read`/`readln` state, and exception globals.
