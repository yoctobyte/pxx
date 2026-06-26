# PXX

PXX is a provisional name for a from-scratch, self-hosting Pascal compiler. It
emits ELF executables directly — no assembler or linker step — for Linux x86-64
(native) plus i386, aarch64, and arm32, with bare-metal ESP32 (xtensa/riscv32)
cross targets. The executable is still `compiler/pascal26`; naming things is the
one compiler problem not solved by recursion.

The compiler is written in plain Pascal and currently supports a tested Object
Pascal subset: classes, generics, overloads, operators, exceptions, RTTI,
component streaming groundwork, C interop, and early BASIC / Nil Python
frontends. The long-term direction is a multi-language native compiler sharing
one IR and backend.

## ⚠️ Security warning — do not expose to a network

PXX is early, unaudited, experimental software. The compiler, its runtime, and
its networking code almost certainly contain bugs — including ones that could be
exploited over a network connection, whether the program acts as a **server or a
client**, and whether the input comes from a remote peer or a file it fetches.

**Do not build or run any publicly reachable network service with software
compiled by PXX**, and do not point a PXX-built client at untrusted remote hosts.
Treat anything it produces as suitable only for local experimentation on inputs
you fully control.

This restriction stands until the compiler, runtime, and networking stack have
been independently tested, hardened, and reach a mature, reviewed state — and
even then the software is provided **without any warranty and with no liability
on the authors** (see [License](#license) and [LICENSE.md](LICENSE.md)). If you
choose to ignore this, you do so entirely at your own risk.

## Highlights

- **Self-hosting:** `make` rebuilds the compiler through the checked-in PXX
  seed and requires a byte-identical fixedpoint before replacing it.
- **Small direct ELF output:** benchmarks report Pascal Hello World in both the
  managed-default string mode and the frozen `-uPXX_MANAGED_STRING`
  compatibility mode; see the newest run in the
  [benchmarks directory](benchmarks/).
- **Fast pipeline:** one in-memory frontend-to-ELF path, no assembler or linker
  subprocess. See the newest run in the [benchmarks directory](benchmarks/).
- **Pascal + C interop:** local C files can be compiled into the same output,
  and supported C headers can be imported directly.
- **Wrapper-free Nil Python C calls:** `.npy` can import `sqlite3` directly and
  run SQLite CRUD without a Pascal wrapper.
- **Embedded direction:** ESP32 codegen (Xtensa and RISC-V) compiles a growing
  subset and emits relocatable `.o` files that link with the ESP-IDF
  toolchains; full ESP-IDF integration is in progress. The plan remains using
  vendor C SDKs directly while keeping generated programs native.

## Quick Start

Prerequisites: Linux x86-64 and GNU `make`. FPC is needed only for bootstrap or
recovery builds.

**Latest stable** (recommended) — clone, then check out the newest stable
release tag:

```sh
git clone https://github.com/yoctobyte/pxx
cd pxx
git checkout "$(git tag -l 'v*.*.*' | awk '!/-/' | sort -V | tail -n1)"   # newest stable tag
make
make test
```

**Current** — the tip of `master` is the live tree (passes its gates; just ahead
of the last stable tag). Skip the checkout to track it:

```sh
git clone https://github.com/yoctobyte/pxx && cd pxx
make && make test
```

> During the `0.x` beta there may be no stable tag yet — use `master`, or check
> out the latest prerelease with `git tag -l` + `git checkout <tag>`.

Bootstrap from FPC (first build on a fresh machine, or recovery):

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

A release is a git tag plus a prebuilt tarball (full source + RTL/PCL + host
binaries + docs in one archive). Tags mark the stable points; the tarballs exist
mainly for offline use, packaging, and distro repackaging — cloning is the
primary path.

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

- [Public documentation](site/index.md) — install, getting started, language,
  features, targets, library, and reference pages.
- [Repository documentation index](docs/README.md)
- [Legacy command line](docs/cli.md)
- [Legacy dialect notes](docs/dialect/README.md)
- [Not implemented](docs/not-implemented.md)
- [Not stable](docs/not-stable.md)
- [Developer docs](docs/developer/README.md)
- [Agent instructions](agents/AGENTS.md) — guidelines and workflow for AI agents working on this repo.

## Repository Layout

- `agents/` - shared AI-agent instructions ([agents/AGENTS.md](agents/AGENTS.md)) and generated code map.
- `benchmarks/` - dated benchmark snapshots.
- `compiler/` - compiler source, the checked-in seed, and `builtin/` (the
  compiler-specific runtime unit auto-included into compiled programs: heap
  allocator, `Str`/`Val`, variant helpers).
- `docs/` - public docs, project state, plans, and historic handovers.
- `lib/` - Pascal library units used by tests and demos (`rtl/`, `pcl/`).
- `stable_linux_amd64/` - stable/recovery compiler binaries. The default channel
  uses managed `AnsiString`; historical managed/frozen channels may remain for
  compatibility.
- `test/` - regression tests, fixtures, and manual harnesses.
- `tools/` - repository maintenance helpers.

## License

No license has been selected or granted yet. This public repository is for
inspection, study, discussion, and project collaboration while the compiler
remains experimental. Do not use it for important, security-sensitive,
safety-sensitive, financial, legal, medical, or infrastructure work, and do not
expose software built with it to a network (see the **Security warning** near the
top of this README).

See [LICENSE.md](LICENSE.md) for the full notice.

## Acknowledgements

PXX depends on [Free Pascal](https://www.freepascal.org/) for bootstrap and on
the Lazarus/FPC ecosystem as a compatibility reference.
