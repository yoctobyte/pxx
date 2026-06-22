# PAL network: datagrams, readiness polling, and exact errno semantics

- **Type:** feature (Track B PAL / networking)
- **Status:** done (POSIX slice; ESP run-validation + IPv6/DNS deferred)
- **Owner:** —
- **Opened:** 2026-06-21 (PAL network slice)
- **Relation:** follows `feature-platform-abstraction-layer`; feeds
  `feature-networking`

## Problem

The first PAL network slice provides the minimum proven IPv4 TCP primitives:
socket, reuseaddr, nonblocking, bind/connect/listen/accept, send/recv, shutdown,
and socket close. POSIX uses raw Linux syscalls; ESP-IDF targets import lwIP
symbols.

Missing surface that should be added deliberately:

- UDP/datagram operations (`sendto`/`recvfrom`) and peer address reporting.
- Readiness polling/select-style waits as PAL primitives, not only the existing
  Linux epoll coroutine reactor.
- Exact errno semantics across POSIX and ESP-IDF/lwIP. Raw Linux syscalls return
  `-errno`, while lwIP returns `-1` and stores the real error in errno.
- ESP-IDF link/run validation with a configured network interface or loopback
  configuration, not only object-level lwIP symbol imports.
- IPv6 and DNS/resolver hooks for the higher-level `feature-networking` API.

## Acceptance

- POSIX PAL has loopback tests for TCP and UDP.
- ESP-IDF PAL links and runs a socket smoke in an IDF app on C3 and S3, with the
  app responsible for network interface bring-up.
- Error returns are documented and consistent enough for `net.pas` and future
  Posix.* shims to distinguish EAGAIN/EINPROGRESS/connection failures.
- The public higher-level networking unit can be written without platform
  conditionals above PAL.

## Log

- 2026-06-21 — Opened after landing the first TCP PAL primitives. These gaps are
  real missing features, not reasons to bend the current PAL code into
  unvalidated workarounds.
- 2026-06-22 — POSIX slice landed (Track B, stable v37):
  - UDP `PalSendToIpv4` / `PalRecvFromIpv4` with peer-address reporting
    (`ParseSockAddrIpv4`), raw `sendto`/`recvfrom` syscalls per arch
    (x86-64/i386 socketcall/aarch64/arm32); i386 needed a 6-arg `SockCall6`.
  - `PalPoll(handle, events, timeoutMs)` readiness primitive via raw `ppoll`
    (chosen over `poll` because aarch64 lacks the legacy syscall); revents
    packed in the second pollfd word, little-endian. New `PAL_POLL_*` bits in
    `platform.pas`.
  - Errno surface widened: raw POSIX syscalls already return `-errno`; added
    `PAL_NET_EWOULDBLOCK`/`ECONNREFUSED`/`ECONNRESET` so `net.pas` and Posix.*
    shims can classify failures without platform conditionals.
  - ESP backend gained matching `lwip_sendto`/`lwip_recvfrom`/`lwip_poll`
    bindings; off-target build returns `PAL_ERR_UNSUPPORTED` (host-asserted in
    `lib_platform_esp`).
  - Verified by `test/lib_platform_net_udp.pas` (loopback UDP echo + poll
    readiness + peer-addr check) wired into `make lib-test`; full gate green.
  - Deferred (not host-validatable here): ESP-IDF link/run smoke on C3/S3 =
    Track A (hardware); IPv6 + DNS/resolver hooks tracked by
    `feature-networking` / `feature-dns-resolver-library`.
  - Landed in commit `db1d3e1`.
