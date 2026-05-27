# Features

PXX is a small native compiler core with Pascal as its primary source
language and early additional frontends/interoperability paths.

## Self-Hosting

The compiler is written in Pascal and compiles itself. Normal builds use the
checked-in PXX seed and require two generated compiler binaries to compare
bit-for-bit. FPC remains the recovery path for rebuilding the seed.

## Native Executable Output

PXX emits x86-64 Linux ELF executables directly:

- No assembler invocation.
- No external linker invocation.
- Static output for programs without external calls.
- Dynamic loader sections when imported shared-library calls are required.
- A generated `.map` file for `_start` and procedures/methods.

## Pascal Frontend

Implemented Pascal capabilities include:

- Basic procedural Pascal, arrays, records, strings, control flow, and units.
- Classes with fields and methods.
- Generic classes and explicitly specialized generic routines.
- Routine overloading and opt-in strict declaration checking.
- Class/record operator implementations.
- Exceptions: untyped `try/except`, `try/finally`, expression raise, and re-raise.
- Conditional compilation with the built-in `PXX` identity symbol.

See [Pascal Dialect And Compatibility](pascal-dialect.md) for syntax and
compatibility policy.

## Multiple Source Languages

The compiler currently selects a frontend based on the input source suffix:

| Input | Status |
| --- | --- |
| Pascal input | Primary, self-hosting frontend. |
| C input (`.c`) | Implemented subset sufficient for covered local C tests. |
| BASIC input (`.bas`) | Present frontend; early/partial and not the project compatibility baseline. |

This is not yet a single mixed-language source format. It is a shared native
compiler containing multiple frontend paths.

## External Library Loading From Pascal

Pascal `uses` can resolve supported C headers and emit external shared-library
calls. The covered example:

```pascal
program TestCType;
uses ctype;
begin
  writeln(tolower(65));
end.
```

`uses ctype;` loads declarations from `/usr/include/ctype.h`, and the
generated ELF requests `libc.so.6`. Only called external functions are
emitted in dynamic symbol and relocation information.

PXX can also compile supported local C source used from Pascal:

```pascal
uses my_c_lib;
```

For the precise unit search order and supported C preprocessor subset, see
[C Interoperability](../C_INTEROP.md).

## C Preprocessing

The C import/input path implements:

- `#include` and common include guards.
- `#define` and `#undef`.
- `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`, and `#endif`.
- Object-like macros and parameter substitution for function-like macros.

This support is deliberately driven by real imported APIs rather than a claim
of full C conformance.

## Development Guarantees

The build suite exercises:

- FPC recovery bootstrap and equivalence checking.
- Recursive self-hosted fixedpoint.
- Pascal language regressions including generics, overloads, operators, loop
  control, and directives.
- C header import, local C compilation, and C preprocessing paths.
