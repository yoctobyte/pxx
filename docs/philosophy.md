# Project Philosophy

## What This Is

PXX is a native compiler written in Pascal that compiles itself.
The immediate goal is a robust, self-hosting Object Pascal compiler
targeting Linux x86-64 ELF — no assembler, no linker, no external
libraries at compile time.

The longer goal is a multi-language native compiler sharing one backend:
a single toolchain where Pascal, C, BASIC, and eventually other languages
coexist, call each other's libraries, and compile to the same native output.
The working nickname for that vision is **Frankonpiler** (or Frankenpiler —
naming is open).

## Design Constraints

- **No external grammar tools.** No lex, yacc, ANTLR, or table-driven DFAs.
  Every frontend is a hand-rolled recursive-descent parser.
- **No external toolchain at runtime.** The compiler writes ELF directly.
  No intermediate assembler invocation, no linker step.
- **Zero external dependencies in compiler source.** No licensed libraries,
  no third-party code. The compiler source must be compilable by a
  standards-conforming Pascal compiler and nothing else.
- **In-memory pipeline.** Lex → parse → codegen → ELF write, all in one
  process, all in RAM. No intermediate files, no assembler round-trip, no
  linker invocation.

## Language Priority

Languages planned for the shared compiler, roughly in priority order:

| Priority | Language | Notes |
|----------|----------|-------|
| 1 | Pascal / Object Pascal | Primary. Self-hosting. FPC-compatible dialect. |
| 2 | C | Core interop. C header import already works. |
| 3 | BASIC | Early frontend present. Not yet a complete implementation. |
| 4 | Ada | High interest. |
| 5 | Rust | High interest. Borrow checker will not be implemented; heap ownership handled by reference counting. |
| 6 | C++ | Partial/limited. |
| 7 | Fortran, COBOL | Partial/limited. |
| 8 | Java (JVM-less) | Interesting native-compilation goal, low priority. |
| – | C# | Experimental / exploratory. |
| – | JavaScript | A strict subset compiles to native without too many surprises. Priority lower than Rust for now. |
| – | Python | Experimental / exploratory. |

Subsets of each language are acceptable. The goal is not spec compliance —
it is useful real-world code compiled natively.

## In-Memory Pipeline

When C was designed, a computer's RAM could easily be smaller than a
project's total source. Compilers were built to process one file at a time
and hand off to the next tool — preprocessor, compiler, assembler, linker —
each reading and writing disk because keeping everything in memory was not
always an option.

On modern hardware, an entire project's source, all symbol tables, all
generated code, and the output binary fit in one process without issue.
PXX loads it all, does it all in one pass, writes the ELF, and exits.

## The Frankenstein Principle

Pick the best tool for the job. A library written in C should be callable
from Pascal without ceremony. A module where Ada's type system gives the
clearest code should be writable in Ada.

The project starts in Pascal because it is a reasonable host language for
a bootstrap story. If a future component is significantly clearer or shorter
in another language, that conversation is open — but only after the
target/host is stable enough to justify it.

## The Self-Hosting Commitment

Normal development never requires FPC. The checked-in seed (`compiler/pascal26`)
compiles the source; the result must reach a bit-identical fixedpoint with the
previous generation before it replaces the seed. FPC is kept only as a
recovery/verification path.

A feature is considered stable for self-hosting only after it passes the
recursive bootstrap check. New features live in tests until then.

## Pascal Source Dialect Policy

The compiler source is kept compatible with FPC. This means:

- No PXX-specific extensions in the compiler's own source.
- `{$ifdef FPC}` branches in the source cover genuine FPC host differences.
- `make fpc-check` verifies FPC can still compile the compiler source.

This is intentionally conservative: keeping FPC as a fallback compiler for
the compiler source is valuable. Extensions to the *target* Pascal dialect
(what PXX accepts from user code) are a separate question.

## Output Targets

- **Primary:** Linux x86-64 ELF.
- **Planned:** ARM64, 32-bit x86.
- **Interest:** Bare-metal / embedded (ESP32-class), no OS.
- **Non-POSIX:** Not yet, but architecture abstraction is the plan from the start.

## What This Is Not

- Not an FPC replacement. FPC has decades of RTL, package ecosystem, and
  multi-architecture support that this project does not claim.
- Not a research compiler. The goal is a working tool, not a novel algorithm.
- Not a transpiler. Output is native ELF, not source-to-source.
- Not complete. Subsets of languages are fine. Unsupported constructs are
  documented in [Limitations](limitations.md).
