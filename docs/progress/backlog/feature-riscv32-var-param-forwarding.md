# riscv32: a var parameter forwarded to a nested var parameter loses its address

- **Type:** bug (Track A — riscv32 codegen)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22 (isolated from the ESP32-C3 lwIP socket smoke, Track B)

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
