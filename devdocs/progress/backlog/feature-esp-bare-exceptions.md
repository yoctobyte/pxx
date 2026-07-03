# ESP bare: try/except (raise currently terminates)

- **Type:** feature (backend parity)
- **Track:** A — `compiler/exception_emit.inc`, ESP backends
- **Status:** backlog
- **Opened:** 2026-07-03
- **Found while:** verifying docs/targets/esp32.md claims (Track D loop).

## Problem

On `--esp-profile=bare` (both chips) the exception runtime is a stub:
ExcSetJmp/ExcLongJmp/ExcRaise all point at EmitExit(1) — a `raise` parks the
program instead of unwinding to a handler. Programs COMPILE cleanly, so the
gap only shows at runtime. Hosted riscv32 got the real setjmp/longjmp frames
on 2026-07-03; the bare profile can reuse the riscv32 machinery verbatim
(nothing about it is hosted-specific — no syscalls except the unhandled
message, which bare should route to UART or skip). xtensa needs its own stub
set (windowed ABI needs care: register windows must be spilled before a
longjmp-style sp rewind).

## Acceptance

- test_cross_exception.pas boots correctly under esp_run_bare.sh on esp32c3
  (riscv32 first; xtensa may split into its own ticket).
- docs/targets/esp32.md caveat updated.

## Log
- 2026-07-03 — Filed by Track A. riscv32-bare = likely small (reuse hosted
  machinery, drop the stderr write); xtensa = larger (windowed ABI).
