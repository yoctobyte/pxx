# Limitations And Not Implemented

This page records boundaries that matter to users selecting PXX today. An
unlisted construct should be treated as unverified until a regression test or
specific compatibility statement covers it.

## Naming And Interface Stability

- `PXX` is provisional. The installed executable is still
  `compiler/pascal26`.
- CLI names, mode behavior, and dialect extensions are early interfaces and
  may be revised while the bootstrap compiler is evolving.

## Platform And Output

- Output target is Linux x86-64 ELF only.
- Cross-compilation targets such as ARM64 or 32-bit are not implemented.
- There is no claim of FPC object, unit-file, package, or linker ABI
  compatibility.

## Pascal Compatibility Gaps

- PXX implements a tested Object Pascal subset, not the full FPC language.
- `{$mode objfpc}` and `-Mobjfpc` are accepted markers, not a complete
  emulation of every Object FPC language rule.
- Alternate Pascal modes such as Delphi mode are not implemented.
- Properties, published RTTI, class references, and virtual/override dispatch
  are implemented for the covered subset. Interfaces, `inherited`, complete
  metaclass syntax, and broader class semantics remain incomplete.
- Exception handling supports catch-all and exact user-class typed
  `try/except` handlers, `try/finally`, `raise <expr>`, and handler re-raise.
  A built-in `Exception` hierarchy, inherited handler matching, message
  constructors, and class/message unhandled reports are not implemented.
- Floating-point support covers `Single` (4-byte SSE2), `Double`/`Real` (8-byte SSE2),
  and `Extended` (10-byte x87 storage, SSE2 arithmetic). Write/WriteLn of float values
  is implemented: fixed form `x:w:n` (exact, IEEE round-to-nearest-even)
  and a bare scientific form (`d.<15 digits>E±ddd`, digits extracted in double precision,
  so the format and last digits differ slightly from FPC). Explicit cast intrinsics
  (Trunc, Round, etc.) are not yet implemented.
- Integer arithmetic is intentionally unchecked for now: no mixed-sign
  warning or overflow/range-check switch is emitted, and narrowing or
  machine-width overflow wraps.
- Scalar ordinal storage is implemented for the existing integer and `Char`
  types. `Byte` and `Char` share a one-byte unsigned representation but are
  distinct numeric/character contexts; `Word` exists as a numeric type, while
  `WideChar` and broader ordinal/range conformance remain future work.
- `Ord` is currently a compiler intrinsic. It may later be surfaced as an RTL
  builtin without requiring ordinary library-call code generation.
- Pointer-sized types and layout (`Pointer`, `NativeInt`, `PtrInt`, class
  references) are defined for x86-64. Named typed pointers, address-of,
  dereference, `nil`, casts, checks, indexing, and record-pointer fields are
  covered. Scaled pointer arithmetic remains future work.
- Generic call-site specialization syntax and alternative generic declaration
  forms are not implemented contracts.
- Set literals, `in` membership, and RTTI-backed set properties work. General
  set assignment, algebra, and comparison are unsafe until the IR gains
  dedicated 32-byte set operations.

## Pascal Directive Gaps

Implemented conditional directives are limited to named symbols:

```pascal
{$define NAME}
{$undef NAME}
{$ifdef NAME}
{$ifndef NAME}
{$else}
{$endif}
```

Missing or incomplete:

- `{$if expression}` and `{$elseif ...}`.
- Define values or macro replacement.
- FPC warning/error/message directives.
- FPC compile switches such as checking, optimization, and code-generation
  states.
- Complete conditional-include semantics; includes are currently expanded
  before Pascal conditional processing.

Unknown Pascal directives are presently ignored as comments. This is useful
for bootstrap source markers, but it is not evidence that their semantics are
implemented.

## Runtime And Units

- PXX does not provide the FPC RTL or its complete set of units.
- Available built-ins and project units cover tested programs only.
- FPC applications depending on `SysUtils`, containers, streams, rich exception classes,
  platform abstractions, or package ecosystems cannot be assumed to compile.

## C Frontend And Interop Gaps

The C capability is useful but intentionally incomplete:

- Header processing and C parsing accept selected practical cases only.
- Token pasting (`##`), stringification (`#`), variadic macros, and complete
  macro rescanning are not supported.
- Complex typedefs/structs, callbacks, variadic functions, and full pointer
  marshalling are not supported as a stable interop surface.
- Library-name resolution has special handling for `ctype`/`libc.so.6`;
  general system-library mapping remains limited.

## BASIC And Further Languages

- BASIC exists as an early frontend, not as a documented complete language
  implementation. The current lexer fixture `test/test_basic_lexer.bas` hangs
  during compilation and BASIC is not part of `make test`.
- Other proposed languages and mixed-source formats are roadmap ideas, not
  implemented user features.

## No Optimization

The IR pipeline does not optimize. Every construct is translated straight to
machine code with no optimization passes (the IR layer exists to enable
this later, but no passes are implemented yet).
What you write is exactly what gets emitted:

- No constant folding, dead-code elimination, or inlining.
- No register allocation — values live in fixed registers per convention.
- No loop transforms, strength reduction, or alias analysis.
- No peephole cleanup of redundant loads/stores.

The IR path is self-host correct: an IR-built compiler reaches
self-recompile fixedpoint and passes `make test` plus `fpc-check`. The obsolete
direct emitter was archived under `docs/historic/` on 2026-05-31.
`--experimental-ir-codegen` remains a deprecated no-op for compatibility.

This is intentional for the bootstrap phase: the compiler stays simple,
self-hostable, and auditable.

## Diagnostics And Tooling

- `--debug` reports compiler tracing; it is not a source debugger.
- Map-file output exists, but general debugging metadata and external tool
  integration are not claimed.
- The command line is project-specific and does not emulate the FPC CLI.

## Inline Assembler

Rudimentary x86-64 inline asm (Intel syntax) is implemented: `asm ... end`
blocks and `assembler` functions, with variables read/written by name. It is
not a full assembler — notably **no labels/branches**, **no global-var
operands**, **no explicit `[reg]` memory**, and **no AT&T syntax**. See
[Inline Assembler](inline-asm.md) for the supported instruction set,
limitations, and TODO.

## How To Read Compatibility Claims

Compatibility is split into separate questions:

| Area | Present claim |
| --- | --- |
| Syntax | Tested Pascal subset only. |
| Semantics | Covered behavior in regression tests only. |
| Directives | Basic named conditional compilation and strict overload mode. |
| RTL | No FPC RTL compatibility claim. |
| ABI | Native ELF/shared-call support only; no FPC ABI claim. |
| Tooling | PXX commands and build flow only. |

The dated summary in [Compatibility Status](../COMPATIBILITY.md) and the
[documentation index](README.md) identify the documentation snapshot. The
implementation may change faster than that snapshot; source and regression
tests are authoritative until the written inventory is refreshed.
