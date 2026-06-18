# Not Implemented

FPC features PXX does **not** support today. Anything not listed and not in a
regression test should be treated as unverified. See
[FPC docs](https://www.freepascal.org/docs.html) for the full language.

## Platform / ABI

- Output is ELF for x86-64/i386/aarch64/arm32 (Linux) and riscv32/xtensa
  (embedded). No other OSes (BSD/macOS/Windows) yet. Binaries are static and
  syscall-only unless they import a shared library; shared-object import
  (dynamic linking) is x86-64 only.
- No FPC object-file, unit-file, package, or linker ABI compatibility.

## Language

- Full FPC Object Pascal — only a tested subset is supported.
- Delphi mode and other alternate modes.
- `is` / `as` / `Supports` runtime type-tests — not implemented even for plain
  classes (ticketed: feature-class-is-as).
- Interfaces (low priority — the OOP-family capstone; feature-interfaces).
- Private/protected access enforcement (parsed, not enforced).
- Built-in `Exception` hierarchy, inherited handler matching, message
  constructors, class/message unhandled reports (low priority).
- Cast intrinsics (`Trunc`, `Round`, ...). Explicit value-casts
  `Char()`/`Boolean()`/`String()` now work (done 2026-06-18); the general
  `TypeName(expr)` reinterpret cast for user-named types is still open
  (feature-general-typename-cast).
- Overflow/range checking — integer arithmetic wraps unchecked.
- `WideChar` and broader ordinal/range conformance.
- Generic call-site specialization sugar (`Max<Integer>(a, b)`).
- Valued `{$define}` and macro replacement; most FPC compile-switch states.

## Runtime / RTL

- The FPC RTL and its units. `SysUtils`, containers, streams, rich exception
  classes, and the package ecosystem cannot be assumed to compile.
- Only tested built-ins and project units are available.
- Float **core works** (arithmetic + formatted `writeln(x:w:d)`, all targets);
  **missing** = transcendental math (`Sqrt`/`Sin`/`Cos`/…, a fallback math
  library) and float `Str`/`Val` (feature-float-str-val).

## C interop

- `##`/`#` macro ops, variadic macros, full macro rescanning.
- Non-integer `#define` macros (string, float, function-like).
- Callbacks, variadic functions, full pointer marshalling as a stable surface.
- `T**` (depth ≥ 2) element typing; out-param auto-address-of (a non-goal).

## Optimization

The IR pipeline does **no** optimization: no constant folding, DCE, inlining,
register allocation, loop transforms, or peephole. What you write is emitted.

## Tooling

- `--debug` is compiler tracing, not a source debugger.
- The CLI is project-specific and does not emulate the FPC CLI.

## Inline assembler

x86-64 Intel-syntax only, with no labels/branches, no global-var operands, no
explicit `[reg]` memory, no AT&T syntax. See
[`developer/inline-asm.md`](developer/inline-asm.md).
