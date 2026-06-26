# PAL esp/lwIP: getsockname & recvfrom return an unfilled (zero) sockaddr

- **Type:** bug (Track B PAL / ESP networking) — qemu-reproducible
- **Status:** backlog — ROOT-CAUSED, blocked-by `feature-riscv32-var-param-forwarding`
- **Owner:** —
- **Opened:** 2026-06-22 (found by the ESP32-C3 lwIP socket smoke under qemu)

## RESOLUTION (2026-06-22): not a PAL bug

Root-caused on-target to a **riscv32 compiler bug**, filed as
`feature-riscv32-var-param-forwarding`: forwarding a `var` parameter into a
nested routine's `var` parameter drops the write on riscv32. `PalGetSockNameIpv4`
/ `PalRecvFromIpv4` call the shared `ParseSockAddrIpv4(@sa, outAddr, outPort)`
with the enclosing function's `var` params, so the parsed address never reaches
the caller. lwIP fills the sockaddr correctly (proven inline). **The PAL code is
correct — no change here; this resolves when the compiler bug is fixed.** The
net-c3 smoke's address read-back checks re-enable then. The analysis below is
kept for the trail.

## Problem

On the ESP-IDF lwIP backend, the address **read-back** PAL calls return an
all-zero sockaddr even though the socket operations themselves succeed:

- `PalGetSockNameIpv4` on a socket explicitly bound to `127.0.0.1:3333` returns
  rc=0 but `outAddr=0.0.0.0`, `outPort=0`.
- `PalRecvFromIpv4` delivers the datagram (3/3 bytes, correct payload) but the
  reported peer is `0.0.0.0:0`.

The **send-side** sockaddr is correct: after fixing `FillSockAddrIpv4` to the
lwIP/BSD layout (`sin_len`@0, `sin_family`@1 — vs the Linux 2-byte family@0 the
POSIX backend uses) the loopback datagram is delivered and `PalPoll` reports it
readable. So bind / sendto / poll / recvfrom-payload all work; only the
out-sockaddr fill is wrong.

The POSIX backend fills these correctly (host `lib_platform_net_udp` peer=ok,
`lib_platform_net_sockopt` name/accept-peer=ok), so it is ESP/lwIP-specific.

## Reproduce

```
cd examples/esp32/net-c3
. ~/esp/esp-idf/export.sh
./build.sh qemu      # boots esp32c3 under qemu-system-riscv32
```
The smoke prints `PXX-net-smoke status=0` (core path) plus diagnostics
`bound-port=0` / `peer-port=0` showing the read-back gap.

## Root-cause analysis (static, 2026-06-22)

Read the IDF lwIP source — the layout/parse side is ruled out:

- `struct sockaddr_in` (lwip/sockets.h): `sin_len`@0, `sin_family`@1 (both
  `u8_t`), `sin_port`@2, `sin_addr`@4 — exactly what `ParseSockAddrIpv4` reads,
  and what the now-fixed `FillSockAddrIpv4` writes (proven by delivery). So parse
  offsets are correct.
- `socklen_t` is `u32_t` (4 bytes) = the PAL's `Integer`. Signature match.
- `lwip_getaddrname()` always calls `netconn_getaddr` then
  `if (*namelen > GET_LEN) *namelen = GET_LEN; MEMCPY(name, &saddr, *namelen);`
  — no input-length gate that would zero a valid request. `lwip_recvfrom`'s
  `from` fill is the same shape.

So an **all-zero** output means lwIP copied **0 bytes**, i.e. it read
`*namelen == 0` on entry — even though the PAL sets `addrlen := 16` before the
call.

Prime suspect: **riscv32 codegen of `@<scalar-local>` passed to an external**.
Note the asymmetry in the same call: `@sa[0]` (address of a local *array*
element, the `from` buffer) reaches lwIP correctly — the payload is received —
but `@addrlen` (address of a local *scalar* `Integer`) appears to arrive as a
pointer to 0 / wrong slot. If confirmed this is a **Track A riscv32 compiler
bug**, not an esp PAL defect, and the PAL code stays as-is (clean scalar `@`).

Cheap discriminator (one qemu cycle, throwaway — do NOT commit a workaround):
in an isolated esp program call `lwip_getsockname` with `addrlen` as a scalar
local vs as `array[0..0] of Integer` element. If the array form fills correctly
and the scalar does not, file the riscv32 `@scalar-local` compiler bug and keep
the PAL on the clean scalar form (blocked on the compiler fix). If both fail,
the cause is lwIP/config and stays here.

All qemu-reproducible (no hardware) via the net-c3 smoke.

## Acceptance

- `PalGetSockNameIpv4` returns the real bound `127.0.0.1:<port>`.
- `PalRecvFromIpv4` reports the loopback peer address/port.
- net-c3 smoke can re-enable the address checks (drop the "diagnostic only"
  caveat) and still print `status=0`.

## Log

- 2026-06-22 — Found wiring the ESP32-C3 lwIP loopback smoke. Send-side sockaddr
  layout fixed (BSD `sin_len`) — datagram delivery now works on real lwIP under
  qemu; read-back side still returns zeros. Filed for root-cause.
