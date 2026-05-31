# PXX Compatibility Status

**Status date:** 2026-05-31

`PXX` is the provisional name for this compiler. It may change before a
public naming/API commitment. Existing executable and stable-seed paths remain
`compiler/pascal26` for now to avoid mixing a branding experiment with
bootstrap history.

This is a dated compatibility snapshot. Implementation may change faster than
the documentation; current source and regression tests take precedence where
the snapshot has not yet been refreshed.

## Identity And Mode Policy

PXX aims to compile a useful FPC/Object Pascal-compatible dialect. Compiler
identity and accepted dialect are separate:

| Symbol or mode | Current meaning |
| --- | --- |
| `PXX` | Predefined when Pascal input is compiled by PXX. |
| `FPC` | Not predefined by PXX. It denotes the actual Free Pascal compiler. |
| `{$mode objfpc}` | Accepted by PXX as the intended compatibility-mode marker; current behavior is already the single implemented dialect. |
| `-Mobjfpc` | Accepted command-line equivalent of the mode marker. |

PXX must not define `FPC` merely because it accepts FPC-like syntax. This keeps
FPC-specific APIs and workarounds from being enabled accidentally in programs
compiled by PXX.

## Pascal Directives

Implemented:

```pascal
{$define NAME}
{$undef NAME}
{$ifdef NAME}
{$ifndef NAME}
{$else}
{$endif}
{$mode objfpc}
{$strict_overload on}   { or off }
{$nestedcomments on}    { or off }
{$cstylecomments on}    { or off }
{$casesensitive on}     { or off }
```

Command line:

```sh
./compiler/pascal26 -dNAME -uOTHER -Mobjfpc --strict-overload source.pas /tmp/out
```

Directive names and defined symbols are case-insensitive. Conditionals nest.
`PXX` cannot be removed with `{$undef PXX}` or `-uPXX`.
`strict_overload` defaults to off; when enabled, every variant of an
overloaded routine must carry `overload;`.
The comment-relaxation switches and strict Pascal casing also default to off.
C-import symbols remain exact-case regardless of the Pascal casing mode.

Current limitations:

- `{$mode objfpc}` is accepted but there are not yet alternate Pascal semantic modes.
- Unknown Pascal directives are currently ignored as comments, allowing existing
  compiler-source markers such as `{$H+}` to pass through.
- `{$if ...}`, `{$elseif ...}`, valued macros, warning directives, and switch
  state such as range checking are not implemented.
- Includes are expanded before Pascal conditional processing; conditional
  inclusion behavior still needs deliberate design and tests.

## Compatibility Matrix

| Area | Current position |
| --- | --- |
| Compiler source bootstrap | `compiler/compiler.pas` is accepted by both FPC and self-hosted PXX; `make bootstrap` and fixedpoint builds are regression requirements. |
| Pascal syntax | A tested subset of Object Pascal is implemented; it is not full FPC syntax compatibility. |
| Pascal directives | Initial define/conditional/identity support exists as listed above; FPC directive coverage is incomplete. |
| RTL and units | Small built-in/runtime surface plus project Pascal units; not FPC RTL compatibility. |
| C interoperability | Simple header imports, selected preprocessing, external calls, and local C bodies; not a full C frontend or ABI surface. |
| Binary/ABI compatibility | Emits x86-64 Linux ELF executables and calls selected shared-library symbols; no claim of FPC object/unit ABI compatibility. |
| Tooling/CLI | Project-specific compiler invocation and build rules; FPC switch compatibility is not claimed. |

## Tested Pascal Surface

Regression-covered behavior includes:

- Programs, constants, variables, integer/Boolean/Char/String operations,
  arrays, records, procedures/functions, `var` parameters, and units.
- `if`, `case`, `while`, `for`, `repeat`, `break`, and `continue`.
- Classes with fields and methods, inheritance, virtual/override dispatch,
  visibility sections, properties, and published RTTI/reflection.
- Generic classes and top-level generic function/procedure specialization.
- Routine overloading and class/record operator implementations.
- `try/except` including exact user-class typed handlers, `try/finally`,
  expression raise, and handler re-raise.
- Pascal conditional definitions and PXX/FPC identity separation.
- Selected C interop and C preprocessing behavior described in
  `C_INTEROP.md`.

## Partial Or Missing Surface

This list is an implementation inventory, not a promise of complete FPC
coverage:

| Feature area | State |
| --- | --- |
| Strict `overload` enforcement | Implemented as opt-in `{$strict_overload on}` / `--strict-overload`; permissive behavior remains the default. |
| Alternative generic syntax and call-site specialization | Planned; current syntax is the tested top-level `generic` / `specialize ... as ...` form. |
| Pascal mode semantics | Only the current objfpc-like subset exists; Delphi/FPC/ISO mode differences are not modeled. |
| Directive expression language and switch state | Missing beyond simple named conditional definitions. |
| Broader Object Pascal model | Exact user-class exception handlers, finalizers, re-raise, properties, class inheritance, virtual dispatch, and published RTTI are covered. Interfaces, `inherited`, complete metaclass syntax, exception hierarchy matching, and rich exception messages remain missing or incomplete. |
| Numeric/type breadth | Fixed-width integer, scalar floating-point, and pointer-sized layout are covered for x86-64. `WideChar`/broader ordinal behavior, float conversion intrinsics, scaled pointer arithmetic, and dedicated set algebra semantics remain incomplete. |
| FPC RTL/packages | Not provided as an FPC-compatible library layer. |
| Cross-target output | Current target is Linux x86-64 only. |

## Bootstrap Conditional Rule

Compiler source still contains host-sensitive `{$ifdef FPC}` branches. Those
branches are legitimate: FPC takes the bootstrap implementation when FPC
compiles the source, while PXX now leaves `FPC` undefined and takes its native
implementation. New code should use:

```pascal
{$ifdef PXX}
  { PXX-specific implementation }
{$endif}
```

for PXX-specific behavior. Do not replace FPC host checks with `{$ifndef PXX}`
unless every possible non-PXX host is intentionally equivalent to FPC.

## Near-Term Work

1. Add the next named semantic switches with explicit defaults and decide
   whether the directive spelling should later be namespaced under `PXX`.
2. Decide the supported `objfpc` subset feature by feature and add conformance
   tests for each claim.
3. Inventory missing Pascal/Object Pascal constructs against real FPC programs
   and classify parse, semantic, RTL, and ABI gaps separately.
4. Grow C header/ABI support only from concrete imported-library test cases.
