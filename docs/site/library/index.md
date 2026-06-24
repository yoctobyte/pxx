---
title: Standard library
order: 30
---

# Standard library

PXX ships its own runtime (RTL) and component library (PCL), written from scratch
with FPC-style naming. This section documents the units a program can `uses`.

> **Status:** in progress. Documented units are verified against the pinned
> compiler.

## Areas

- Core RTL — strings, dynamic arrays, `IntToStr`/`Copy`/`Length`, file I/O.
- SysUtils-style helpers.
- Collections — `TList`, `TStringList`, …
- Networking, hashing, JSON, and more as they land.

_(Stub — Track C fills these in.)_
