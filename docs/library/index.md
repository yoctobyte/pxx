---
title: Standard library
order: 50
---

# Standard library

PXX ships its own runtime (RTL) and component library (PCL), written from scratch
with FPC-style naming. This section documents the units a program can `uses`.

The `pxx` wrapper created by `install.sh` adds the bundled library roots, so most
programs can use these units without passing extra `-Fu` flags.

## Core units

| Unit | Area |
| --- | --- |
| `sysutils` | String and conversion helpers such as `IntToStr`, plus common utility routines. |
| [`classes` & `streams`](./core.md) | Object, list, and stream infrastructure (lists, string lists, memory streams) for FPC-style code. |
| `textfile` | Pascal text-file support. |
| `math` | Numeric helpers. |
| `typinfo` | RTTI inspection helpers. |

Several language features also have runtime support in the default environment:
managed strings, dynamic arrays, exceptions, interfaces, classes, RTTI, and file
I/O are available without importing a unit just to initialize the runtime.

## Data and formats

| Unit | Area |
| --- | --- |
| [`json`](./json.md) | JSON parser / serializer support. |
| `httpjson` | HTTP helpers for JSON payloads. |
| `base64` | Base64 encoding and decoding. |
| `png` / `image` | Image decoding and simple bitmap support. |
| `zlib` | Compression support. |

## Networking and async

| Unit | Area |
| --- | --- |
| [`http`](./networking.md) | HTTP/1.1 client with redirects, chunked responses, pooling, and TLS backend support. |
| `net` / `sockets` | Lower-level networking primitives. |
| `dns`, `dns_async` | DNS lookup helpers. |
| `scheduler`, `coroutine`, `asyncnet` | Coroutine reactor and async networking support. |
| `tls`, `tls_openssl` | TLS backend interface and OpenSSL-backed implementation. |

## Crypto and checksums

| Unit | Area |
| --- | --- |
| `sha256`, `sha512`, `hashing` | Hashing helpers. |
| `random` | Random byte and number helpers. |
| `aesgcm`, `chacha20poly1305` | Authenticated encryption primitives. |
| `ed25519`, `ecdsa_p256`, `x25519`, `rsa`, `x509` | Public-key and certificate building blocks. |
| `tls13_*` | Native TLS 1.3 handshake/key/record work in progress. |

## Terminal, UI, and PCL

| Unit | Area |
| --- | --- |
| `ansiterm`, `ansirender`, `screen`, `lineedit`, `menu` | Terminal UI helpers. |
| `forms`, `controls`, `stdctrls`, `extctrls`, `dialogs`, `menus` | PCL component-library units. |
| `gtk3`, `gtk3widgets`, `glarea`, `graphics` | GTK/OpenGL-backed GUI pieces used by demos and the Eliah IDE. |

## Platform units

The wrapper installs the POSIX platform backend by default. Cross and embedded
flows may pass an explicit platform root when a helper asks for it, for example
an ESP backend path in an ESP32 object build.

For project-local units, pass additional roots with `-Fu`:

```sh
./pxx -Fusrc app.pas app
```

## Status

The library is still young. Treat these pages as the user-facing map of what is
intended to be usable from applications; if a documented call fails on the pinned
compiler, that is either a docs bug or a compiler/library regression worth filing
as a progress ticket.
