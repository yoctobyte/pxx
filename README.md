# PXX (Provisional)

PXX is a small self-hosting Pascal compiler for Linux x86-64. It emits ELF
executables directly, without an assembler or linker.

The compiler is written in plain Pascal and currently compiles a tested Object
Pascal subset with classes, generics, overloads, operators, exceptions, C
interop, and early BASIC / Nil Python frontends. The longer-term direction is a
multi-language native compiler sharing one backend and IR. See
[Philosophy](docs/philosophy.md) for the vision.

## Highlights

- **Tiny output** — Pascal Hello World is 287 bytes. No runtime or stdlib is
  linked in. See the [runtime-gate benchmark](benchmarks/2026-06-02-runtime-gate.md).
- **Fast** — single in-memory pipeline; no assembler round-trip, no linker
  invocation. See the [compiler-runtime benchmark](benchmarks/2026-06-03-compiler-runtime.md)
  for FPC-built vs self-hosted compiler runtime.
- **C + Pascal in one static binary** — `uses my_c_lib;` compiles a local C
  source file and merges it into the output ELF. No linker step, no separate
  `.so`. Pascal and C code share one binary with no external dependencies.
- **Wrapper-free C from Nil Python** — `.npy` can import `sqlite3` directly and
  run SQLite CRUD with no Pascal wrapper; the compiler lifts C out-params and
  copies returned `char*` values. See
  [Wrapper-Free C From Nil Python](docs/wrapper-free-c-from-nil-python.md).
- **Embedded direction** — ESP32/ESP-IDF is a long-term target: use the vendor C
  SDK directly, treat FreeRTOS as a target profile, and keep the program native.
  See [ESP32 And ESP-IDF Direction](docs/esp32-esp-idf-roadmap.md).
- **Self-contained build path** — the compiler writes ELF directly and can
  rebuild itself from the checked-in seed. FPC remains the bootstrap and
  recovery tool.
- **Generic functions and procedures** — `generic function Max<T>` +
  `specialize Max<Integer> as MaxInt`, alongside class generics.
- **Overloading and operators** — routine overloading with optional strict
  mode, plus `operator +(a, b: TPoint): TPoint` class operator implementations.
- **Exceptions (Phase 1)** — `try/except`, `try/finally`, `raise <expr>`, and
  re-raise; generated jump-frame runtime, no libc dependency.
- **IR-native backend** — Pascal lowers through an explicit IR before x86-64
  emission. The IR pipeline reached full self-recompile fixedpoint on
  2026-05-28; the obsolete direct emitter was archived on 2026-05-31.
- **Published RTTI + reflection** — `published` properties/methods emit a
  compact RTTI blob; `compiler/typinfo.pas` walks it at runtime
  (`GetClass`/`GetPropList`/`Get|SetOrdProp`/`Get|SetStrProp`/`SetMethodProp`,
  including enum and set properties). Built on typed pointers (named aliases,
  `p[i]`, `p^.field`, `PType(expr)` casts). Groundwork for component streaming.
- **FPC-compatible source** — the compiler itself is valid FPC Pascal.
  `make fpc-check` verifies this. FPC is the bootstrap tool and a respected
  reference implementation.

## Quick Start

### Prerequisites

- Linux x86-64
- GNU `make`
- FPC only for bootstrap/recovery builds

### Self-Hosted Build

Uses the checked-in PXX seed. No FPC needed.

```sh
git clone https://github.com/yoctobyte/pxx
cd pxx
make
make test
```

### Bootstrap From FPC

Use this when the checked-in seed is missing, stale, or intentionally being
reseated.

```sh
sudo apt install fpc
git clone https://github.com/yoctobyte/pxx
cd pxx
make bootstrap
make test
make test-nilpy
make fpc-check
```

Both paths require byte-identical fixedpoint before replacing
`compiler/pascal26`.

### Optional PATH Symlink

For contributor builds, point `pxx` at the mutable self-hosted seed:

```sh
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/compiler/pascal26" "$HOME/.local/bin/pxx"
```

For a stable/recovery binary, point it at the recorded latest stable build:

```sh
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/stable_linux_amd64/default/latest" "$HOME/.local/bin/pxx"
```

## Debug Tracing

```sh
./compiler/pascal26 --debug source.pas /tmp/out
```

Reports lexer/parser diagnostics and C preprocessing events.

## Project Notes

Start with the [documentation index](docs/README.md) for the command line,
Pascal dialect, supported features, and explicit limitations.
The dated [project-state audit](docs/project-state.md) is the shortest current
inventory of verified support, confirmed bugs, missing Pascal features, and
design debt.

Design decisions, dialect proposals, and bootstrap history live in
`compiler/usernotes.md`. The dated compatibility inventory is tracked in
[docs/compatibility.md](docs/compatibility.md).

The project vision — multi-language compiler, design constraints, language
priority list — is in [docs/philosophy.md](docs/philosophy.md).

## Repository Layout

- `agents/` — shared AI-agent instructions and the generated code map
  (`agents/codemap/symbols.md`).
- `benchmarks/` — dated benchmark snapshots.
- `compiler/` — compiler source, runtime support units, and the checked-in
  self-hosted seed executable.
- `docs/` — public docs, current project state, plans, and historic handovers.
- `lib/` — Pascal library units used by tests and demos.
- `stable_linux_amd64/` — Linux x86-64 stable/recovery binaries, split into
  `default/` and `managed/` channels with `latest` symlinks.
- `test/` — regression tests, fixtures, and manual harnesses.
- `tools/` — repository maintenance helpers.

## License And Use Notice

No license has been selected or granted yet. This repository is public so the
code can be inspected, studied, and discussed for research and educational
purposes while the project remains experimental.

Do not use this compiler for security-sensitive, safety-sensitive, financial,
legal, medical, infrastructure, or otherwise important work. Public visibility
on GitHub does not grant permission to copy, modify, distribute, sublicense,
sell, or otherwise use the code beyond what applicable law independently
allows, and it does not make the author responsible for any consequences of
use or reliance.

See [LICENSE.md](LICENSE.md) for the full notice.

## Acknowledgements

[Free Pascal](https://www.freepascal.org/) and [Lazarus](https://www.lazarus-ide.org/)
are the bootstrap and the ecosystem this project depends on. None of it exists
without Ada Lovelace, who wrote the first algorithm before the machine to run
it existed, or without everyone who kept building from there.

The full lineage — Pascal, C, Ada, BASIC, GW-BASIC, FPC, and everyone else —
is in [docs/lineage.md](docs/lineage.md).
