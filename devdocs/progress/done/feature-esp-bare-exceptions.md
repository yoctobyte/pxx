# ESP bare: try/except (raise currently terminates)

- **Type:** feature (backend parity)
- **Track:** A — `compiler/exception_emit.inc`, ESP backends
- **Status:** done
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
- 2026-07-03 — Implemented (Track A), BOTH chips (xtensa did not need its
  own ticket). riscv32 bare: reuse the hosted setjmp/longjmp frames verbatim
  (condition widened; only the unhandled-message write(2) is skipped on
  bare — an unhandled raise parks via EmitExit(1) as before). xtensa Call0:
  new stub set in exception_emit.inc (jmpbuf = a15, sp, a0 — the direct
  Call0 mirror of riscv32's s0/sp/ra; stub entries nop-padded to 4-byte
  alignment for call0) + full IR_EXC_ENTER/LEAVE/RAISE/STORE/MATCH/
  MATCH_HIT/CLEAR set in the xtensa walker (EXC_FRAME_SIZE_XT=32, moving-sp
  frames). Windowed ABI: clean compile error (register windows would need
  spilling before an sp rewind); bare already rejects windowed. Verified:
  test/test_esp_exception.pas (except/finally/re-raise/nested) UART-matches
  the x86-64 oracle on esp32c3 AND esp32s3; wired into `make test-esp-bare`.
  Hosted riscv32 exception gate still green. esp32.md caveat updated.
