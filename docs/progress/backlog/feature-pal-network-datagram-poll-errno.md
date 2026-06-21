# PAL network: datagrams, readiness polling, and exact errno semantics

- **Type:** feature (Track B PAL / networking)
- **Status:** backlog
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
