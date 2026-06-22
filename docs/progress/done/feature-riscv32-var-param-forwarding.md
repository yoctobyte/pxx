# riscv32: a var parameter forwarded to a nested var parameter loses its address

- **Type:** bug (Track A — riscv32 + xtensa codegen)
- **Status:** DONE — 2026-06-22 (fixed on BOTH ESP backends; xtensa had the same defect).
- **Owner:** — (Track A)
- **Opened:** 2026-06-22 (isolated from the ESP32-C3 lwIP socket smoke, Track B)
- **Closed:** 2026-06-22

## Problem

On `--target=riscv32`, when a routine receives a `var` parameter and passes it as
the argument to another routine's `var` parameter, the write performed by the
inner routine does **not** reach the caller's variable — the forwarded address is
wrong (the inner write lands on a local/stale slot). One level of `var` works;
forwarding `var` → `var` through a call does not.

x86-64, i386, aarch64, and arm32 all handle this correctly (the host and
qemu-user `lib_platform_net_sockopt` tests, which do exactly this via
`PalGetSockNameIpv4` → `ParseSockAddrIpv4`, pass on all four).

## Minimal repro (riscv32, observed under qemu-system-riscv32 / esp32c3)

```pascal
procedure inner(var p: Integer);
begin
  p := 3333;
end;

procedure outer(var op: Integer);
begin
  inner(op);          { var op forwarded to inner's var p }
end;

var x: Integer;
begin
  x := 0;
  inner(x);   { direct  -> x = 3333  (works) }
  x := 0;
  outer(x);   { forwarded -> x stays 0 on riscv32 (BUG); 3333 elsewhere }
end.
```

Confirmed on real esp32c3 lwIP under qemu: a local `myParse(@sa, aLocal, pLocal)`
fills `pLocal=3333`, but `outer(@sa, a, p)` that forwards its `var` args into
`myParse` yields `p=0`. (`docs/progress/backlog/feature-pal-esp-lwip-sockaddr-readback.md`
has the full trace.)

## Impact

Breaks `PalGetSockNameIpv4` / `PalRecvFromIpv4` on riscv32/ESP: they call the
shared `ParseSockAddrIpv4(@sa, outAddr, outPort)` with the enclosing function's
`var` params, so the parsed address never reaches the caller — getsockname and
recvfrom report `0.0.0.0:0` even though lwIP filled the sockaddr correctly. The
PAL code is idiomatic and correct; the fix is in the backend.

## Acceptance

- The repro above sets `x = 3333` via `outer` on `--target=riscv32`.
- `PalGetSockNameIpv4` / `PalRecvFromIpv4` report the real address on esp32c3
  (the net-c3 smoke re-enables its address checks).
- Self-host fixedpoint + existing riscv32 codegen tests stay green.

## Log

- 2026-06-22 — Isolated from the ESP32-C3 lwIP socket smoke. Bisected on-target:
  inline lwIP getsockname fills the sockaddr (port 3333); a direct
  `myParse(...local out vars...)` works; only the `var`→`var` forwarded form
  returns 0. riscv32-specific (cross-arch i386/aarch64/arm32 var→var works).

- 2026-06-22 — **Attempted (Track A), HALTED: needs an ESP/qemu-system harness.**
  riscv32 and xtensa are bare-metal/ESP targets — they are NOT in
  `make cross-bootstrap` (only i386/aarch64/arm32 are) and do NOT run under
  qemu-USER here: even `program h; begin Halt(7); end.` for `--target=riscv32`
  hangs (timeout) under `tools/run_target.sh riscv32`. So none of the ESP codegen
  items can be runtime-verified in the host loop; verification requires
  qemu-system / the esp-bare / IDF flow (as this ticket's own repro notes:
  "qemu-system-riscv32 / esp32c3"). Deferred to a session with that harness wired
  (or real esp32c3/s3 hardware) so fixes ship verified, not blind.
- 2026-06-22 — static-read note for the next attempt: the obvious forwarding path
  LOOKS correct — `EmitSlotAddrRISCV32` (ir_codegen_riscv32.inc ~205) already
  dereferences a var-param slot (`lw rd,(rd)`) to yield the forwarded caller
  address, and `IR_LEA` (~712) routes through it. So the defect is subtle (not
  the headline "address-of var param" path); pin it with on-target disasm of
  `outer`'s call to `inner` (how the `var op` arg is materialised into a2).

## Fix log

- 2026-06-22 — **FIXED on riscv32 AND xtensa.** Root cause (found via disasm under
  the Espressif qemu-system harness): `IR_LEA` of a `var`/`out` SCALAR param
  returned the local slot ADDRESS (`&slot`), not the forwarded caller pointer
  (`[slot]`). `EmitSlotAddrRISCV32` / `EmitSlotAddrXtensa` (the scalar slot-addr
  emitters that `IR_LEA` uses) never dereferenced var params, while the 64-bit
  siblings (`EmitSlotAddr64*`) and the load/store paths already did — so Int64
  var params worked but 32-bit scalars didn't. So forwarding `var op` into another
  routine's `var p` (and `@op`) passed `&op_slot`; the callee wrote a stale local.
  Fix: in each backend's `IR_LEA` handler, deref the slot for a scalar by-ref
  param (`skParam and IsRef and not IsArray and TypeKind<>tyAnsiString`) — one
  branch each in `ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`. Arrays and
  managed strings keep their existing handling; `IR_SLOTADDR` and the store paths
  (which need the raw slot address) are untouched.
- **HARNESS NOTE (reverses the earlier "needs harness" halt):** the ESP
  qemu-system harness already exists and works — `tools/esp_run_bare.sh --chip
  esp32c3|esp32s3 <prog>` boots a `--esp-profile=bare` ELF and diffs UART vs the
  x86-64 oracle (`make test-esp-bare`). The earlier halt used qemu-USER
  (`run_target.sh`), which is wrong for these bare-metal targets. Both Espressif
  qemus are installed here.
- Test: `test/test_esp_varparam.pas`, wired into `make test-esp-bare` for both
  chips (oracle-diff). esp32c3 + esp32s3 both report `direct=3333 / fwd=3333`.
  make test + cross-bootstrap byte-identical.
