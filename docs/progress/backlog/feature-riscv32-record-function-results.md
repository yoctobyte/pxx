# riscv32: support record (by-value struct) function results

- **Type:** feature (Track A — riscv32 codegen / ABI)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22 (found wiring net.pas onto the ESP32-C3 socket smoke, Track B)

## Problem

The riscv32 backend rejects a function whose result is a record (small struct
returned by value):

```
target riscv32: only ordinal/float/pointer/string function results supported yet
```

Per the RISC-V calling convention a struct ≤ 2 XLEN words is returned in
`a0`/`a1`; larger aggregates use the hidden-pointer (sret) convention. Neither
is emitted yet. x86-64 handles record returns (net.pas works on host).

## Impact (why it surfaced)

`lib/rtl/net.pas` exposes `TNetAddress` (a 2-field record: `Host: LongWord;
Port: Integer`) and the helpers `NetAddress`/`NetLoopback` return it by value.
That makes net.pas itself fail to compile for `--target=riscv32`, so the
blocking net facade cannot be used on ESP32-C3. The PAL layer (`platform`) has
no record-returning functions and compiles + links fine for riscv32 — the
ESP32-C3 lwIP socket smoke (`examples/esp32/net-c3`) therefore calls PAL
directly instead of net.pas. This is a real codegen gap, not a reason to
restructure net.pas: returning a small record by value is idiomatic Pascal.

Note Int64 results: a function returning `Int64` works on riscv32 when the
result is consumed directly (the PAL byte-count functions do this); only record
results are blocked here.

## Acceptance

- A function returning a ≤ 2-word record compiles for `--target=riscv32`,
  result marshalled in `a0`/`a1`, caller reads both fields correctly.
- Larger records use the sret hidden-pointer convention.
- `--target=riscv32 -Fulib/rtl/platform/esp` over a program that `uses net`
  (e.g. `NetLoopback`) compiles and links.
- Self-host fixedpoint + existing riscv32 codegen tests stay green.

## Log

- 2026-06-22 — Opened from the ESP32-C3 socket-smoke wiring. PAL-direct path
  works on riscv32; net.pas's by-value `TNetAddress` helpers do not. Sibling
  xtensa gap: `feature-xtensa-stack-args-over-6-words`.

- 2026-06-22 — **Attempted (Track A), HALTED: needs an ESP/qemu-system harness.**
  riscv32 and xtensa are bare-metal/ESP targets — they are NOT in
  `make cross-bootstrap` (only i386/aarch64/arm32 are) and do NOT run under
  qemu-USER here: even `program h; begin Halt(7); end.` for `--target=riscv32`
  hangs (timeout) under `tools/run_target.sh riscv32`. So none of the ESP codegen
  items can be runtime-verified in the host loop; verification requires
  qemu-system / the esp-bare / IDF flow (as this ticket's own repro notes:
  "qemu-system-riscv32 / esp32c3"). Deferred to a session with that harness wired
  (or real esp32c3/s3 hardware) so fixes ship verified, not blind.
