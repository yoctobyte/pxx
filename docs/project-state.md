# Project State Audit

**Audited:** 2026-05-31

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
records, strings, classes, constructors, inheritance, virtual/override and
abstract dispatch, visibility parsing, properties, published RTTI, reflection,
resources, LFM streaming, procedure/method pointers, integer and float
arithmetic, typed pointers, dynamic arrays of scalar values, exceptions,
generics, overloads, operators, inline asm, `goto`, `with`, comments, case
modes, allocator builtins, `read`/`readln`, and selected RTL helpers.

Case behavior is per origin:

- Pascal declarations are case-insensitive by default.
- `{$CASESENSITIVE ON}` enables strict Pascal declaration matching.
- C imports remain exact-case because emitted ELF link names are exact.

## Confirmed Bugs

- **BASIC lexer fixture hangs.** Compiling `test/test_basic_lexer.bas` did not
  terminate during this audit. BASIC remains experimental and is not part of
  `make test`.

## Major Missing Pascal Features

- Interfaces, initially a CORBA-style no-refcount model; see `todo.md` section
  3.
- Full `class of` syntax and general metaclass typing. The LCL slice has the
  narrower class-reference behavior it needs.
- Scaled pointer arithmetic (`p + n`); pointer indexing works.
- Float conversion intrinsics such as `Trunc`, `Round`, `Int`, and float
  `Str`/`Val`.
- Dynamic arrays beyond scalar elements and basic resize behavior: record or
  string elements, params/results, reference counting, copy-on-grow, and
  reclaim.
- Aggregate-valued function results still need a deliberate ABI. Set-valued
  function results compile but are not supported yet.
- Full access-control enforcement. Visibility sections are parsed and
  `published` drives RTTI, but private/protected checks are intentionally not
  enforced yet.
- FPC directive breadth: conditional expressions, switch state, warning/error
  directives, and complete conditional include behavior.
- Qualified `UnitName.Symbol` resolution and broader unit namespace/import
  behavior.

## Broader Design Debt

- Active compiler internals are still one include-heavy translation unit.
- Several compiler record layouts are hardcoded in `symtab.inc`; extending
  those records requires synchronized metadata changes and often an FPC
  bootstrap.
- The allocator uses a simple first-fit free list with no splitting,
  coalescing, bins, or large-block `munmap`.
- There are no IR optimization passes, register allocation, or additional CPU
  targets.
- The C importer needs substantially deeper preprocessing, typedef, struct,
  callback, and ABI support before real GTK/glib headers replace handwritten
  bindings.
- Automated GUI tests remain separate because they require GTK/display
  environment handling.
