---
title: Compatibility status
order: 89
---

# Compatibility status

This page summarises what PXX compiles and runs today, across both frontends and
the bundled libraries. It is a snapshot of the standing test suites and the
real-world corpora PXX is exercised against; the automated gates are the source of
truth, and current numbers may move ahead of this page.

## What "works" means here

A corpus is listed as **working** when it compiles with PXX, runs, and its output
matches a reference. Two distinct kinds of "identical" appear below, and they are
**not** the same claim:

- **Self-host reproducibility** — the PXX compiler, rebuilt by the previous PXX
  binary, reproduces that binary **byte for byte**. This is about the compiler's
  own output being deterministic.
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
| **c-testsuite** | The full standard C conformance battery passes. |
| **zlib** | Compresses with output **byte-for-byte identical to a gcc-built zlib's** output. |
| **SQLite** | The amalgamation compiles and runs — in-memory and file-backed databases, CRUD, and multi-threaded access — as a **libc-free, zero-dependency** binary. |
| **Lua** | The reference interpreter compiles and runs Lua programs. |
| **cJSON** | Parses and serialises. |
| **tcc** (Tiny C Compiler) | Compiles, and a PXX-built tcc in turn compiles tcc itself (self-compile converged). |

### Partial / in progress

- **QuickJS** — the JavaScript-via-C route is a work in progress.
- A number of candidate corpora (graphics, networking, and game libraries) are
  staged for bring-up but not yet claimed.

## Pascal frontend

PXX targets the Object Pascal language as Free Pascal accepts it (see
[FPC compatibility](../language/fpc-compatibility.md)).

### Bundled libraries

The PXX RTL and standard libraries pass a broad smoke suite, including:

- **Core**: strings, `sysutils`, `classes`, collections, streams, formatting,
  paths, big integers, fixed/rational numerics, bitsets, complex numbers.
- **Data**: JSON, base64, a PNG encoder, an embedded VM / interpreter samples.
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

Against the FPC test-suite conformance subset, the large majority of curated
programs pass. Known gaps concentrate in `UnicodeString`/`WideString`
conversions, some `ShortString` edge cases, parts of the generics corpus, and
`{$Q+}` overflow semantics on 64-bit integers. These are tracked and shrinking.

## Cross-targets

The figures above describe the x86-64 host. PXX also cross-compiles to i386,
AArch64, ARM32, RISC-V 32, Xtensa, and ESP32; most of the above runs there too,
but per-target status is a separate axis with its own gates.

## How this is measured

Status is produced by the project's own test manager and watcher, which run the
smoke suites, the conformance batteries, and the real-world corpora on every
change and publish per-revision reports. The gates — not this page — are
authoritative for the current moment.
