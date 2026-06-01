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

- **BASIC lexer fixture hangs.** Compiling `test/test_basic_lexer.bas` did not
  terminate during this audit. BASIC remains experimental and is not part of
  `make test`.

## Major Missing Pascal Features

- Interfaces are intentionally deferred until a concrete compatibility target
  needs them; see `todo.md` section 3.
- Metaclass aliases are pointer-backed and do not yet enforce every descendant
  constraint against arbitrary pointer-compatible assignments.
- Float conversion intrinsics such as `Trunc`, `Round`, `Int`, and float
  `Str`/`Val`.
- Managed `AnsiString`: current strings are inline fixed-capacity values.
  Reference-counted heap strings need an explicit cross-thread sharing policy
  before their ABI is fixed, because thread-safe refcounts imply atomic or
  equivalent synchronization overhead.
- Dynamic arrays beyond scalar elements and basic resize behavior: record or
  string elements, params/results, reference counting, copy-on-grow, and
  reclaim. Deepen these after allocator and managed-`AnsiString` work.
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
  coalescing, bins, or large-block `munmap`.
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
