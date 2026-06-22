# PAL esp/lwIP: getsockname & recvfrom return an unfilled (zero) sockaddr

- **Type:** bug (Track B PAL / ESP networking) — qemu-reproducible
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-22 (found by the ESP32-C3 lwIP socket smoke under qemu)

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

## Suspects / next steps

- `*addrlen` (socklen_t in/out) handling into `lwip_getsockname` /
  `lwip_recvfrom`: confirm the value passed (16) and what lwIP writes back. The
  PAL passes `@addrlen` to an `Integer` initialized to 16.
- Whether `ParseSockAddrIpv4` reading port@2-3 / addr@4-7 matches what lwIP
  writes (offsets are layout-invariant vs Linux, so this is unlikely, but verify
  against a raw 16-byte dump of the returned buffer).
- Whether IDF lwIP needs the input `from`/`name` buffer pre-tagged (sin_len /
  family) before the call, or a CONFIG_LWIP_* option, to populate the output.
- This is fully qemu-reproducible (no hardware needed) via the net-c3 smoke, so
  it can be root-caused on host.

## Acceptance

- `PalGetSockNameIpv4` returns the real bound `127.0.0.1:<port>`.
- `PalRecvFromIpv4` reports the loopback peer address/port.
- net-c3 smoke can re-enable the address checks (drop the "diagnostic only"
  caveat) and still print `status=0`.

## Log

- 2026-06-22 — Found wiring the ESP32-C3 lwIP loopback smoke. Send-side sockaddr
  layout fixed (BSD `sin_len`) — datagram delivery now works on real lwIP under
  qemu; read-back side still returns zeros. Filed for root-cause.
