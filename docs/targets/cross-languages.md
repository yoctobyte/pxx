---
title: Cross languages
order: 62
---

# Cross languages

PXX is centered on Pascal, but the compiler has experimental alternate
frontends that share backend infrastructure.

## Frontends by suffix

| Suffix | Frontend |
| --- | --- |
| `.pas`, `.pp` | Pascal |
| `.c` | C |
| `.bas` | BASIC, experimental |
| `.npy` | Nil Python, experimental |

The Pascal frontend is the supported user-facing path. The other frontends exist
to test interop and backend reuse, and their accepted language subsets are still
moving.

## C Frontend

PXX features a C frontend that compiles `.c` source files directly to native executables. It supports a substantial subset of C, featuring a libc-free runtime and the "magic link" model.

See the dedicated [C Frontend](./c-frontend.md) page for details on compiling C, the linking model, and library configuration.

## C interop

PXX can import selected C headers and call shared-library symbols on supported
paths. This is useful for concrete bindings, but it is not a full C compiler or
full C ABI compatibility layer.

## Nil Python

Nil Python is an experimental Python-like frontend designed to call imported C
APIs directly through the same compiler backend. It supports strict local type inference and automatic C-parameter return-lifting (autotyping).

See the dedicated [Nil Python](./nil-python.md) page for detailed syntax, type inference rules, and C-interop capabilities.

## Next

- [FPC compatibility](../language/fpc-compatibility.md)
- [Targets](./)
