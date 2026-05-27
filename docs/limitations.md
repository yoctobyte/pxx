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
- Broader Object Pascal features such as properties, interfaces, virtual
  dispatch, and related class semantics are not covered as supported.
- Exception handling supports untyped `try/except`, `try/finally`,
  `raise <expr>`, and handler re-raise. Typed handlers, exception classes,
  and class/message unhandled reports are not implemented.
- Floating-point support is not implemented.
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
  references) are defined for x86-64. General pointer syntax and operations,
  including typed pointers, address-of, dereference, `nil`, casts, and checks,
  remain future work.
- Generic call-site specialization syntax and alternative generic declaration
  forms are not implemented contracts.

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
  implementation.
- Other proposed languages and mixed-source formats are roadmap ideas, not
  implemented user features.

## Diagnostics And Tooling

- `--debug` reports compiler tracing; it is not a source debugger.
- Map-file output exists, but general debugging metadata and external tool
  integration are not claimed.
- The command line is project-specific and does not emulate the FPC CLI.

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
