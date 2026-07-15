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

If a documented example fails against the pinned compiler, file a progress ticket
under `devdocs/progress/backlog` with the command, source, expected result, and
actual result.

## Next

- [Command line](./cli.md)
- [FPC compatibility](../language/fpc-compatibility.md)
- [Targets](../targets/)
