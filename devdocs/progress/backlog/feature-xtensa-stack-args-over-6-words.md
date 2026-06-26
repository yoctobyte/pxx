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

- 2026-06-22 — **Attempted (Track A), HALTED: needs an ESP/qemu-system harness.**
  riscv32 and xtensa are bare-metal/ESP targets — they are NOT in
  `make cross-bootstrap` (only i386/aarch64/arm32 are) and do NOT run under
  qemu-USER here: even `program h; begin Halt(7); end.` for `--target=riscv32`
  hangs (timeout) under `tools/run_target.sh riscv32`. So none of the ESP codegen
  items can be runtime-verified in the host loop; verification requires
  qemu-system / the esp-bare / IDF flow (as this ticket's own repro notes:
  "qemu-system-riscv32 / esp32c3"). Deferred to a session with that harness wired
  (or real esp32c3/s3 hardware) so fixes ship verified, not blind.
- 2026-06-22 — **Verified the threshold empirically (not just inferred from one
  compile error).** Programs defining + calling a procedure with N Integer
  params, `--target=xtensa`: `5` and `6` params compile; `7` and `8` FAIL with
  `more than 6 parameter words not yet supported`. Holds for BOTH `--xtensa-abi=
  windowed` and Call0 (bare). The definition-site error (parser.inc:10557) fires
  first for a 7-word routine, which is the `PalBackendVforkAndExec` (7 words)
  case. So: xtensa supports <= 6 param words, >6 does not compile — confirmed,
  not assumed.

- 2026-06-22 — **CORRECTION: the ESP harness DOES exist** (the earlier "needs
  qemu-system harness" halt note was wrong — it used qemu-USER). Use
  `tools/esp_run_bare.sh --chip esp32c3|esp32s3 <prog>` (UART vs x86-64 oracle,
  the `make test-esp-bare` pattern); both Espressif qemu-system builds are
  installed. So this item is runtime-verifiable now. Sibling
  feature-riscv32-var-param-forwarding was fixed+verified this way (f67fad2). This
  one remains a real codegen feature (record-return ABI / xtensa stack args), but
  it is no longer blocked on verification.

- 2026-06-23 — Scoped (Track A). The cap is at parser.inc ~10823/10840 (callee
  param copy) + ir_codegen_xtensa.inc ~1549 (call site). Lifting it needs INCOMING
  STACK-ARG layout: words 0-5 stay in a2-a7 (Call0) / a10-a15 (windowed), words 6+
  go on the stack and the callee reads them from its incoming frame. **Call0** is
  the tractable half (classic moving-sp overflow; offset = frame size + saved regs
  + (k-6)*4). **Windowed is the rabbit hole** and is exactly what the blocked PAL
  needs (`--xtensa-abi=windowed`): the `entry`/`retw` window rotation plus the
  [sp-16] window spill area make the overflow-arg offset frame-and-window
  dependent — not a clean extension. Deferred as a focused sub-task; needs careful
  windowed frame-layout work (and the qemu-system harness, which now exists, to
  verify). The sibling ESP items (var->var forwarding, record results) are DONE
  and verified this session; this is the remaining one.
