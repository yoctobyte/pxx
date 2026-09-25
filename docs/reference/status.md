---
title: Compatibility status
order: 89
---

# Compatibility status

This page summarises what PXX compiles and runs today, across its frontends and
the bundled libraries.

> **For current numbers, read the live status pages, not this page.**
> <https://pxxc.org/status/> is generated from the test manager's own output on
> every content pull — [conformance](https://pxxc.org/status/conformance/) has
> the exact per-category pass/fail counts,
> [tests](https://pxxc.org/status/tests/) the watcher's per-revision verdicts,
> and [benchmarks](https://pxxc.org/status/benchmarks/) the timings.
>
> What follows is the part that does *not* move week to week: what the claims
> mean, and which corpora are exercised. Deliberately no figures — a number
> written here is a number that starts going stale the day it is written.

## What "works" means here

A corpus is listed as **working** when it compiles with PXX, runs, and its output
matches a reference. Two distinct kinds of "identical" appear below, and they are
**not** the same claim:

- **Self-host reproducibility** — the PXX compiler, rebuilt by the previous PXX
  binary, reproduces that binary **byte for byte**. This is about the compiler's
  own output being deterministic. It is proved **at the default optimisation
  level**: the rebuild passes no `-O` flag, and nothing in the per-change gate
  self-compiles at another one, so this says the compiler reproduces itself at
  one optimisation level rather than at every level.
- **Behavioural (output) parity** — a program compiled with PXX produces the same
  **output** as the same program compiled with the reference toolchain. For
  example, zlib built with PXX emits a compressed stream **byte for byte identical
  to the stream emitted by a zlib built with gcc**. PXX does **not** emit the same
  machine code as gcc, and does not claim to.

## C frontend

The C frontend compiles standard C directly to native ELF in a single pass (see
[C Frontend](../targets/c-frontend.md)).

### Working

| Corpus | What it demonstrates |
| --- | --- |
| **c-testsuite** | All 220 programs of the standard C conformance battery pass (pin v425, x86-64, 2026-09-25). |
| **zlib** | Compresses with output **byte-for-byte identical to a gcc-built zlib's** output. |
| **SQLite** | The amalgamation compiles and runs — in-memory and file-backed databases, CRUD, and multi-threaded access — as a **libc-free, zero-dependency** binary. A multi-threaded (`--threadsafe`) build needs the C runtime from a checkout at or after `3f28aafab`; with pin v425's own checkout it hangs in `sqlite3_open`. |
| **Lua** | The reference interpreter compiles and runs Lua programs. |
| **cJSON** | Parses and serialises. |
| **QuickJS** (quickjs-ng 0.9.0) | The JavaScript engine compiles as a zero-dependency binary and runs the in-tree smoke test byte-for-byte. |
| **tcc** (Tiny C Compiler, mob at `a338258d`) | PXX compiles `tcc.c`. That tcc builds a C program byte-identical to the one a GCC-built tcc builds, and compiles `tcc.c` into a tcc byte-identical to the GCC-built tcc's, which then reproduces itself (pin v425, 2026-09-25). See the `-run` note below. |
| **tiny-regex-c** | Its three test programs print the same as the GCC build; `test1` passes 76 of 76 (pin v425). |
| **ENet** 1.3.18 (commit `5a9c537f`) | A reliable-UDP networking library: a server and a client in one program connect over localhost and exchange a packet each way, with output identical to the GCC build (pin v425). |
| **BusyBox** | Compiles as separate translation units, BusyBox's own way, with output **matching a GCC build of the same sources** across a differential case list. A PXX-built BusyBox also boots as PID 1 under a real kernel — see [A minimal Linux system](../examples/minimal-linux-system.md). |

### Partial / in progress

- **`tcc -run`** runs a C program in memory instead of writing a file, so tcc
  has to load the host's C library at run time. Both PXX builds of tcc link
  glibc's `libc.so.6` dynamically. The default build cannot use `-run`: it
  stops with `libc.so.6: unrecognized file type`. Build tcc with
  `-dPXX_DYNLIB_LIBC` and `-run` works, `-lm` included:
  `pascal26 -dPXX_DYNLIB_LIBC -DONE_SOURCE=1 tcc.c tcc`, with `libtcc1.a` and
  `runmain.o` in tcc's `-B` directory. With v425, 135 of the 137 programs in
  tcc's `tests/tests2` print the same under `-run` as with a GCC-built tcc.
  The two that differ are fixed in the development tree: a `double` converted
  to a 64-bit unsigned integer saturates at 2^63 (`60de228a1`, a compiler fix),
  and `#pragma once` does not recognise a header included by another path,
  because `realpath` did not resolve the path (`3ee6e2431`, in the C runtime,
  so a checkout at or after it gives 136 of 137 with v425).
- A number of candidate corpora (graphics, networking, and game libraries) are
  staged for bring-up but not yet claimed.

## Pascal frontend

PXX is an Object Pascal **dialect** of its own. It follows FPC's behaviour for
much of the language and compiles real FPC code, but full FPC parity is not the
goal — see [the PXX dialect](../language/dialect.md) for what it adds and
[FPC compatibility](../language/fpc-compatibility.md) for what ports. Parity
checks are opt-in per rule rather than on by default
([compiler modes](./modes.md)).

So "works" below means *this dialect compiles and runs the code*, not *PXX is
indistinguishable from FPC*. Where the two disagree deliberately, the divergence
is recorded rather than filed as a bug.

### Bundled libraries

The PXX RTL and standard libraries pass a broad smoke suite, including:

- **Core**: strings, `sysutils`, `classes`, collections, streams, formatting,
  paths, big integers, fixed/rational numerics, bitsets, complex numbers.
- **Data**: JSON, base64, a PNG encoder *and* decoder (round-tripped in the
  gate), an embedded VM / interpreter samples.
- **Cryptography**: SHA-256/512, HMAC/HKDF, ChaCha20-Poly1305, X25519, AES-GCM,
  RSA and Ed25519 and ECDSA-P256 verification, X.509.
- **Networking**: a full **TLS 1.3** stack (key schedule, record layer,
  handshake), an **HTTP** client and server (async, redirect, keep-alive,
  connection pooling, gzip, cookies, JSON), and DNS (async, caching).
- **System**: sockets, processes, dynamic libraries, terminal UI.

### Real-world FPC libraries

| Library | Status |
| --- | --- |
| **fcl-json** (fpjson) | Its own test suite passes in full under `--mimic-fpc`. |
| **Synapse** | The HTTP/crypto helper chain runs (base64, MD5, SHA-1, CRC-32, URL, TCP/UDP). |
| **fgl** | Generic containers run. |
| **fcl-fpcunit** | The unit-testing framework runs. |

### Language conformance

PXX is run against Free Pascal's own test suite. The
[live conformance page](https://pxxc.org/status/conformance/) carries the
current pass/fail/skip counts per category, and distinguishes a real
unimplemented feature (`gap`) from a probe of FPC internals or a deliberate
divergence (`wontfix`) — the two should never be added together.

Known gaps concentrate in `UnicodeString`/`WideString` conversions, some
`ShortString` edge cases, parts of the generics corpus, and `{$Q+}` overflow
semantics on 64-bit integers. These are tracked and shrinking.

## Nil Python frontend

Nil Python (`.npy`) is a compiled Python-shaped dialect, not a Python
implementation. It is python-ish: a useful core behaves as under CPython, and
outside that core it is known to have plenty of issues — see
[Nil Python](../targets/nil-python.md) for the core, the measured limits, and
where it differs on purpose. It carries its own gate rather than riding on
the Pascal one.

### Working

| Area | What it demonstrates |
| --- | --- |
| **Standing `.npy` suite** | Several hundred test programs in-tree, covering classes and dunder methods, variants, `str`/`bytes`/`list`/`set`/`tuple`/`dict` surfaces, lambdas and capture, optionals, file I/O, and exceptions reaching the RTL. |
| **CPython as the oracle** | For `re`, `collections.Counter`, `dataclasses` field defaults and PEP 604 annotation unions, the expected output in the gate *is* CPython's own output for the same program. |
| **`import sqlite3`** | Gives Python's `sqlite3` API (`connect`, `execute`, iterating rows) as PXX's own module layered over the system `libsqlite3.so.0`, so the database engine is SQLite itself, not a reimplementation. The module covers part of Python's API. With `--no-shims`, the same import reads `sqlite3.h` and calls the C API directly. CRUD against a file-backed database is part of the gate. |

The claim here is narrower than for the C corpora: this is a standing suite plus
a differential check against CPython on specific modules, not a conformance
battery. Coverage of the language surface is deliberately partial, and the gaps
are documented rather than implied.

## The other frontends

`pxx --version` lists twelve frontends. The three above are the ones with a
compatibility status worth stating; the rest are covered by
[Other frontends](../targets/other-frontends.md), which says plainly which is
which:

- **BASIC** is a real frontend with its own dialect and regression tests.
- **Rust** and **Zig** are experimental and deliberately parked short of general
  use.
- **Ada, Fortran, Algol, Erlang, LOLCODE and Whitespace** are skeleton probes —
  one test each. They exist to prove the shared AST and IR are correct by
  feeding them programs shaped unlike anything the mainline frontends emit, and
  a probe has no compatibility status worth tabulating. Their presence in
  `--version` is not a support claim.

## Cross-targets

Everything above describes the x86-64 host. PXX also cross-compiles to i386,
AArch64, ARM32 and 32-bit RISC-V (Linux), to `wasm32` (WebAssembly, run with
wasmtime), and to the ESP32's `riscv32` and `xtensa`: seven backends in all.
Most of the above runs on the cross targets too, but per-target status is a
separate axis with its own gates; [Targets](../targets/index.md#what-each-target-supports)
has the per-target table, measured on the previous pin, v424.

## How this is measured

Status is produced by the project's own test manager and watcher, which run the
smoke suites, the conformance batteries, and the real-world corpora on every
change and publish per-revision reports. The gates — not this page — are
authoritative for the current moment.

### What this page can still get wrong

The gates keep the *numbers* honest, and this page carries none. What they do
not check is the **prose** — a claim here can quietly stop describing the
compiler without any test going red, and that failure runs in one direction:
docs understate what works, because a feature ships and the sentence saying it
does not is never revisited. The structural claims above (which frontends exist,
what each corpus demonstrates, what the two "identical" claims mean, which
targets are real) were last re-checked against the pinned compiler on
**2026-08-29**, pin v393.

If something here disagrees with what the compiler in front of you does, the
compiler is right and this page is stale. `pxx --version`, `pxx --list-targets`
and `pxx --doctor` answer three of those questions directly, without a source
file.
