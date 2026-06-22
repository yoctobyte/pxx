# xtensa: support calls/definitions with more than 6 parameter words

- **Type:** feature (Track A — xtensa codegen / ABI)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22 (found during PAL esp object-smoke, Track B)

## Problem

The xtensa backend caps both function **definitions** and **call sites** at 6
parameter words:

- `compiler/parser.inc:10557` / `:10573` — defining a routine with > 6 parameter
  words → `target xtensa: more than 6 parameter words not yet supported`.
- `compiler/ir_codegen_xtensa.inc:1528` — a call passing > 6 argument words →
  `target xtensa: more than 6 call argument words not supported yet`.

riscv32 already allows 8 (`parser.inc:10523`); x86-64/aarch64/arm32 spill to the
stack. xtensa needs the same: arguments beyond the in-register set (a2..a7 for
Call0, the rotated window for windowed) go on the outgoing stack frame per the
Xtensa ABI; the callee reads them from its incoming frame.

## Impact (why it surfaced)

The **esp32s3 (xtensa) PAL object build is blocked**. `PalBackendVforkAndExec`
(`lib/rtl/platform/{posix,esp}/platform_backend.pas`) takes 7 parameter words
(`path, argv, envp, stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd`), so
`--target=xtensa --xtensa-abi=windowed -Fulib/rtl/platform/esp
test/lib_platform_esp.pas` fails at pascal26:647. This predates the PAL
datagram/introspection work — it landed with the process-spawning feature. The
**esp32c3 (riscv32) build is fine** (8-word cap) and imports all expected
`lwip_*`/process symbols.

No workaround applied: the 7-word `PalBackendVforkAndExec` signature is the
honest one (mirrors the POSIX fork+exec plumbing). It stays clean; the fix is in
the compiler.

## Acceptance

- A routine defined with 7+ parameter words compiles for `--target=xtensa`
  (both Call0 and windowed ABIs), args beyond the register set passed on the
  stack, callee reads them correctly.
- A call site passing 7+ argument words marshals the overflow to the outgoing
  stack slots.
- `--target=xtensa --xtensa-abi=windowed -Fulib/rtl/platform/esp
  test/lib_platform_esp.pas <obj>` emits an object importing the expected
  `lwip_*` symbols (parity with the riscv32 esp object smoke).
- Self-host fixedpoint + existing xtensa codegen tests stay green.

## Log

- 2026-06-22 — Opened from a Track B PAL esp object-smoke: riscv32 esp object
  compiles and imports `lwip_sendto/recvfrom/poll/getsockopt/getsockname`;
  xtensa esp object fails on the pre-existing 7-word `PalBackendVforkAndExec`.
  Related broader target ticket: `feature-esp32-idf-xtensa`.
