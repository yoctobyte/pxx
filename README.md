# PXX (provisional)

A self-hosting Pascal compiler that emits x86-64 Linux ELF executables
directly — no assembler, no linker, no external libraries required.

`PXX` is the working name. The X's are open: Roman twenty-six, a pair of
crosses — apt for a compiler that crosses languages — or honest placeholders.
The executable stays `compiler/pascal26`. The spirit of the project has a
better name: **Frankonpiler**. *Frankenstein Pascal Compiler* was already taken.

The compiler itself is written in plain standard Pascal (no OOP, no external
deps). It compiles Object Pascal: classes, generics (class generics and
generic functions/procedures), routine and operator overloading, exceptions,
C interop, and more.

The longer-term goal is a multi-language native compiler — Pascal first,
then C, BASIC, and eventually others — sharing one backend and one IR.
See [Philosophy](docs/philosophy.md) for the vision.

Focus: Linux / POSIX. Single target for now: x86-64.

## Highlights

- **Tiny output** — Hello World is 325 bytes. No runtime, no stdlib linked in.
- **Fast** — single in-memory pipeline; no assembler round-trip, no linker invocation.
- **C + Pascal in one static binary** — `uses my_c_lib;` compiles a local C
  source file and merges it into the output ELF. No linker step, no separate
  `.so`. Pascal and C code share one binary with no external dependencies.
- **Zero-dependency self-hosting** — the compiler writes ELF directly. No
  assembler, no linker, no external libraries invoked at compile time. It
  compiles itself.
- **Generic functions and procedures** — `generic function Max<T>` +
  `specialize Max<Integer> as MaxInt`, alongside class generics.
- **Overloading and operators** — routine overloading with optional strict
  mode, plus `operator +(a, b: TPoint): TPoint` class operator implementations.
- **Exceptions (Phase 1)** — `try/except`, `try/finally`, `raise <expr>`, and
  re-raise; generated jump-frame runtime, no libc dependency.
- **FPC-compatible source** — the compiler itself is valid FPC Pascal.
  `make fpc-check` verifies this. FPC is the bootstrap tool and a respected
  reference implementation.

## Build

### Prerequisites

- Linux x86-64
- GNU `make`
- FPC (Free Pascal Compiler) — needed for `make bootstrap` and `make fpc-check`; not required for a normal `make` if the seed is intact

On Debian/Ubuntu: `sudo apt install fpc`

### Normal build

Uses the checked-in self-hosted seed binary. No FPC required.

```sh
git clone https://github.com/yoctobyte/pxx
cd frankonpiler
make        # rebuild compiler from the existing seed
make test   # full regression suite + fixedpoint check
```

The seed is `compiler/pascal26`. `make` rebuilds it through itself and
verifies the result is bit-identical (gen1 == gen2 fixedpoint).

### Bootstrap from FPC

FPC (Free Pascal Compiler) is the bootstrap tool. It rebuilds the seed from
scratch when needed:

```sh
make bootstrap
```

After bootstrap the compiler is self-hosting again: the new seed must reach
a bit-identical fixedpoint before it replaces the working compiler.

During active development, bootstrapping via FPC is still common — it is the
fastest way to recover when a change breaks self-compilation. The long-term
goal is that `make bootstrap` becomes rare, but it is a normal and supported
workflow for now, not a last resort.

`make fpc-check` verifies at any time that FPC can still compile the
compiler source; this keeps the bootstrap path healthy.

## Debug Tracing

```sh
./compiler/pascal26 --debug source.pas /tmp/out
```

Reports lexer/parser diagnostics and C preprocessing events.

## Project Notes

Start with the [documentation index](docs/README.md) for the command line,
Pascal dialect, supported features, and explicit limitations.

Design decisions, dialect proposals, and bootstrap history live in
`compiler/usernotes.md`. The dated compatibility inventory is tracked in
[COMPATIBILITY.md](COMPATIBILITY.md).

The project vision — multi-language compiler, design constraints, language
priority list — is in [docs/philosophy.md](docs/philosophy.md).

## Acknowledgements

[Free Pascal](https://www.freepascal.org/) and [Lazarus](https://www.lazarus-ide.org/)
are the bootstrap and the ecosystem this project depends on. None of it exists
without Ada Lovelace, who wrote the first algorithm before the machine to run
it existed, or without everyone who kept building from there.

The full lineage — Pascal, C, Ada, BASIC, GW-BASIC, FPC, and everyone else —
is in [docs/lineage.md](docs/lineage.md).
