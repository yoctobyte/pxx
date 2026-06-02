# Features

PXX is a small native compiler core with Pascal as its primary source
language and early additional frontends/interoperability paths.

## Baseline Build Constraint

The compiler is written in Pascal and must be able to compile itself. This is
the minimum viability bar for development, not a headline language feature.
Normal builds use the checked-in PXX seed and require two generated compiler
binaries to compare bit-for-bit. FPC remains the recovery path for rebuilding
the seed.

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
- Classes with fields and methods, virtual/override dispatch, and properties.
- Class visibility sections and minimal published RTTI (`System.TypInfo`-named).
- Procedure and method references (`@routine`, `@obj.method` → `TMethod`).
- Generic classes and explicitly specialized generic routines.
- Routine overloading and opt-in strict declaration checking.
- Class/record operator implementations.
- Exceptions: `try/except` including exact user-class typed handlers,
  `try/finally`, expression raise, and re-raise.
- Conditional compilation with the built-in `PXX` identity symbol.

See [Pascal Dialect And Compatibility](pascal-dialect.md) for syntax and
compatibility policy.

## Multiple Source Languages

The compiler currently selects a frontend based on the input source suffix:

| Input | Status |
| --- | --- |
| Pascal input | Primary, self-hosting frontend. |
| Nil Python input (`.npy`) | Python-shaped static dialect; shares the Pascal AST/IR. Supports `import name` (routed to the unit/C-header resolver), classes, control flow, Variant, and space-separated `print`. |
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

A Pascal routine can also bind a shared-library symbol directly, without a C
header, which suits libraries whose headers are impractical to import:

```pascal
procedure gtk_init(argc, argv: Pointer); cdecl; external 'libgtk-3.so.0';
```

PXX can also compile supported local C source used from Pascal:

```pascal
uses my_c_lib;
```

A real library is driven end-to-end this way: `test/test_sqlite_crud.pas`
imports `/usr/include/sqlite3.h`, links `libsqlite3.so.0`, and runs a full
open/exec/prepare/step/columns round-trip. `PChar(s)` marshals a Pascal string
to a C `const char*`.

## External Library Loading From Nil Python

Nil Python reaches the same resolver through `import name`:

```python
import sqlite3
print(sqlite3_libversion_number())
```

For a pointer-heavy API, a thin Pascal binding unit holds the pointers and
exposes string/integer calls that `.npy` imports — see
`lib/rtl/sqlitedb.pas` and `test/test_nilpy_sqlite_crud.npy` (full SQLite CRUD
from Nil Python), and the plan in
[`handover-nilpy-c-binding-2026-06-02.md`](handover-nilpy-c-binding-2026-06-02.md).

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

## IR Backend

Pascal is lowered through an explicit linear IR before x86-64 emission. The
compiler bootstraps through this path and reached full self-recompile
fixedpoint on 2026-05-28 (three consecutive IR-compiled compiler generations
are bit-identical). The obsolete direct AST-to-machine-code emitter was
archived under `docs/historic/` on 2026-05-31. `--experimental-ir-codegen`
remains a deprecated no-op for compatibility.

`--dump-ir` prints the IR without changing the emitted binary.

## Inline Assembler

Rudimentary x86-64 inline assembler (Intel syntax): `asm ... end` statement
blocks and `assembler`-modifier function bodies. Pascal locals and params are
referenced by name (resolved to their `[rbp+disp32]` frame slot), so asm can
read and write variables directly. See [Inline Assembler](inline-asm.md) for
the supported instruction set and current limits.

## GUI (GTK3 + LFM Streaming)

An early LCL-compatible GUI layer runs on GTK3 (Linux/X11). It is pure library
code over the language: a hand-written `external` binding to `libgtk-3.so.0`,
LCL-named classes (`TForm`, `TButton`, `TApplication`), `of object` events
(`OnClick`), and binary form (`.lfm`) streaming that instantiates and wires a
component tree by class name and event identifier. See [GUI](gui.md).

## Development Guarantees

The build suite exercises:

- FPC recovery bootstrap and equivalence checking.
- Recursive self-hosted fixedpoint.
- Pascal language regressions including generics, overloads, operators, loop
  control, and directives.
- C header import, local C compilation, and C preprocessing paths.
