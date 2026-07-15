---
title: Licensing
order: 95
---

# Licensing

PXX is open source, licensed **per directory**. Every source file carries a
one-line `SPDX-License-Identifier` header; the table below is the map. The
authoritative copy lives in
[`LICENSE.md`](https://github.com/yoctobyte/pxx/blob/master/LICENSE.md) at the
repository root.

| Path | License |
| --- | --- |
| `compiler/**` (except `compiler/builtin/`) | MPL 2.0 |
| `tools/**` | MPL 2.0 |
| `compiler/builtin/**`, `lib/rtl/**`, `lib/pcl/**`, `lib/crtl/**`, `lib/asmcore/**` | zlib |
| `examples/**` | 0BSD |
| `docs/**` | CC BY 4.0 |
| everything else (tests, devdocs, build files) | MPL 2.0 |

## Why the split

The runtime and libraries — everything under the **zlib** license — are
**embedded into every binary the compiler produces**. Because zlib carries no
attribution or copyleft obligation, programs you compile with PXX are entirely
yours: the toolchain adds no license strings to your output.

The compiler itself is **MPL 2.0**: use it anywhere, link it with anything, ship
products built with it — but published modifications to the compiler's own source
files stay open under the same license. MPL's copyleft is file-scoped, so it does
not reach into code you merely compile or link against.

Examples are **0BSD** (public-domain-equivalent, no attribution required) so you
can lift a demo into your own project without ceremony. These documentation
pages are **CC BY 4.0**.

## What this means for you

- **Programs you build with PXX:** no obligations from the toolchain. The
  embedded runtime is zlib-licensed and imposes nothing on your binary.
- **Shipping the compiler or a modified compiler:** MPL 2.0 applies. You may
  distribute it commercially; you must make source for any modified MPL files
  available under MPL.
- **Reusing example code:** 0BSD — copy freely, no attribution needed.
- **Reusing these docs:** CC BY 4.0 — reuse with attribution.

This is informational, not legal advice; the license texts in the repository
(`LICENSE`, `licenses/Zlib.txt`, `licenses/0BSD.txt`) are the binding terms.

## Next

- [Command line](./cli.md)
- [Current limits](./limits.md)
