---
title: Current limits
order: 92
---

# Current limits

PXX is experimental. This page collects practical limits a user should know
before treating a successful compile as a production-ready result.

## General use

- Do not use PXX-built programs for security-sensitive, safety-sensitive,
  financial, legal, medical, infrastructure, or public network-facing workloads.
- The supported surface is what is tested in this repository. Uncovered FPC
  language or RTL behavior may compile incorrectly or not compile at all.
- Error messages are improving, but some unsupported constructs still fail with
  compiler-internal wording.
- **The runtime reserves a 256 MiB heap arena.** The first heap allocation in
  any PXX program maps 256 MiB in a single `MAP_PRIVATE|MAP_ANONYMOUS` request.
  Pages fault in lazily, so actual use stays small — a string-concatenating test
  program peaks at 392 KB resident and the compiler at about 15 MB compiling it
  — but the mapping is requested *without* `MAP_NORESERVE`, so a small VM,
  container, or memory-capped environment can refuse it, and the program then
  exits with `pxx: out of memory (heap arena mmap failed)` before doing any
  work. A program that allocates nothing (a `writeln` of a literal) makes no
  such request. Measured 2026-09-10 on x86-64 Linux.

## Language and compatibility

- PXX does not implement the full Free Pascal language and RTL.
- `{$mode objfpc}` and `-Mobjfpc` are accepted as compatibility markers, not as
  a switch to a complete FPC semantic mode.
- Some FPC directives are accepted only as comments or compatibility markers.
- Range (`{$R+}`), overflow (`{$Q+}`), and IO (`{$I+}`) checking are implemented
  but **opt-in per region** — the lax default does not check. Many other
  compile-switch states are still accepted only as inert markers. See
  [directives](./directives.md).
- The FPC package ecosystem is not bundled.
- A routine, a procedural type or a method takes at most 32 parameters, and
  a method's `Self` counts as one. A 33rd is refused with `too many
  parameters (33, max 32, counting Self for a method)`. FPC has no such
  limit; pass a record instead. Pin v448 and earlier crashed the compiler
  with no message here. Measured 2026-09-28 with v449 (sha256
  `0ded1e5d04c8`): 32 parameters compile and run as in FPC 3.2.2, 33 are
  refused.

## Targets

- Linux `x86_64` is the primary path.
- Linux `i386`, `aarch64`, and `arm32` are cross-output targets with growing
  test coverage.
- `riscv32` and `xtensa` are embedded/ESP32-oriented targets. Treat them as
  active bring-up surfaces rather than stable general-purpose release targets.
- `--shared` (`.so` output) is x86-64 only, introduced for and validated with
  the `.asm` assembly-source frontend.

## Libraries

- Library documentation describes the intended user-facing surface, but the RTL
  and PCL are still young.
- HTTPS requires a registered TLS backend. The OpenSSL backend is opt-in and
  depends on a system `libssl`.
- Some GUI examples require GTK/OpenGL development libraries and a display
  server.

## Reporting gaps

If a documented example fails against the pinned compiler, open an issue at
<https://github.com/yoctobyte/pxx/issues> with the command, the source, the
result you expected and the result you got.

## Next

- [Command line](./cli.md)
- [FPC compatibility](../language/fpc-compatibility.md)
- [Targets](../targets/index.md)
