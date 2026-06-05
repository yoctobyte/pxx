# PXX

PXX is a provisional name for a small self-hosting Pascal compiler for Linux
x86-64. It emits ELF executables directly, with no assembler or linker step.
The executable is still `compiler/pascal26`; naming things is the one compiler
problem not solved by recursion.

The compiler is written in plain Pascal and currently supports a tested Object
Pascal subset: classes, generics, overloads, operators, exceptions, RTTI,
component streaming groundwork, C interop, and early BASIC / Nil Python
frontends. The long-term direction is a multi-language native compiler sharing
one IR and backend.

## Highlights

- **Self-hosting:** `make` rebuilds the compiler through the checked-in PXX
  seed and requires a byte-identical fixedpoint before replacing it.
- **Tiny output:** Pascal Hello World is 287 bytes with no linked runtime; see
  the [runtime-gate benchmark](benchmarks/2026-06-02-runtime-gate.md).
- **Fast pipeline:** one in-memory frontend-to-ELF path, no assembler or linker
  subprocess. See the [compiler-runtime benchmark](benchmarks/2026-06-03-compiler-runtime.md).
- **Pascal + C interop:** local C files can be compiled into the same output,
  and supported C headers can be imported directly.
- **Wrapper-free Nil Python C calls:** `.npy` can import `sqlite3` directly and
  run SQLite CRUD without a Pascal wrapper.
- **Embedded direction:** ESP32/ESP-IDF is a future target; the plan is to use
  vendor C SDKs directly while keeping generated programs native.

## Quick Start

Prerequisites: Linux x86-64 and GNU `make`. FPC is needed only for bootstrap or
recovery builds.

Self-hosted build:

```sh
git clone https://github.com/yoctobyte/pxx
cd pxx
make
make test
```

Bootstrap from FPC:

```sh
sudo apt install fpc
git clone https://github.com/yoctobyte/pxx
cd pxx
make bootstrap
make test
make test-nilpy
make fpc-check
```

The bootstrap path reseats `compiler/pascal26` only after the self-built
compiler reaches byte-identical fixedpoint.

## Using The Compiler

Compile and run a Pascal source file:

```sh
./compiler/pascal26 test/hello.pas /tmp/hello
/tmp/hello
```

Enable compiler tracing:

```sh
./compiler/pascal26 --debug source.pas /tmp/out
```

Optional PATH symlink for active development:

```sh
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/compiler/pascal26" "$HOME/.local/bin/pxx"
```

Optional PATH symlink for the latest recorded stable compiler:

```sh
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/stable_linux_amd64/default/latest" "$HOME/.local/bin/pxx"
```

## Documentation

- [Documentation index](docs/README.md)
- [Command line](docs/cli.md)
- [Dialect](docs/dialect.md)
- [Not implemented](docs/not-implemented.md)
- [Not stable](docs/not-stable.md)
- [Developer docs](docs/developer/README.md)
- [Agent instructions](agents/AGENTS.md) — guidelines and workflow for AI agents working on this repo.

## Repository Layout

- `agents/` - shared AI-agent instructions ([agents/AGENTS.md](agents/AGENTS.md)) and generated code map.
- `benchmarks/` - dated benchmark snapshots.
- `compiler/` - compiler source, runtime support units, and checked-in seed.
- `docs/` - public docs, project state, plans, and historic handovers.
- `lib/` - Pascal library units used by tests and demos.
- `stable_linux_amd64/` - stable/recovery compiler binaries, split into
  `default/` and `managed/` channels with `latest` symlinks.
- `test/` - regression tests, fixtures, and manual harnesses.
- `tools/` - repository maintenance helpers.

## License

No license has been selected or granted yet. This public repository is for
inspection, study, discussion, and project collaboration while the compiler
remains experimental. Do not use it for important, security-sensitive,
safety-sensitive, financial, legal, medical, or infrastructure work.

See [LICENSE.md](LICENSE.md) for the full notice.

## Acknowledgements

PXX depends on [Free Pascal](https://www.freepascal.org/) for bootstrap and on
the Lazarus/FPC ecosystem as a compatibility reference.
