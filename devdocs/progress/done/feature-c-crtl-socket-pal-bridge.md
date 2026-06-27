# crtl: BSD socket wrappers over PAL IPv4 sockets

- **Type:** feature
- **Status:** done
- **Track:** B (`lib/crtl`) with C/pin handoff
- **Opened:** 2026-06-27

## Goal

Expose the minimal BSD C socket surface in `lib/crtl` without importing libc:
`sys/socket.h`, `netinet/in.h`, `arpa/inet.h`, and a `socket.c` veneer that
converts C `sockaddr_in` to the existing PAL IPv4 socket primitives.

This mirrors the stdio/file bridge: C code should call a C-shaped API, while the
actual platform work remains in `lib/rtl/platform.pas` and its selected backend.

## Acceptance

- C headers declare IPv4 socket types/constants and the common calls:
  `socket`, `bind`, `connect`, `listen`, `accept`, `send`, `recv`, `sendto`,
  `recvfrom`, `shutdown`, `setsockopt`, `getsockopt`, `getsockname`.
- `lib/crtl/src/socket.c` implements those calls through `pxxcio` PAL bridges,
  not libc imports.
- Regression `test/csocket_loopback_b88.c` performs a TCP loopback connect,
  accept, send, recv, and close, returning 42.

## Log

- 2026-06-27 — Implemented in working tree (commit pending): added
  `sys/socket.h`, `netinet/in.h`, `arpa/inet.h`, `lib/crtl/src/socket.c`,
  `pxxcio` bridge functions, and Makefile test wiring. Regression
  `test/csocket_loopback_b88.c` covers TCP loopback (`socket`/`setsockopt`/
  `bind`/`listen`/`connect`/`accept`/`send`/`recv`/`close`) and UDP loopback
  (`getsockname`/`sendto`/`recvfrom`). Verified with:
  `stable_linux_amd64/default/pinned compiler/compiler.pas /tmp/pxx-socket-g1`
  then `/tmp/pxx-socket-g1 -Ilib/crtl/include -Ilib/crtl/src
  test/csocket_loopback_b88.c /tmp/csocket_loopback_b88_g1`; the binary returns
  42. Pinned v81 itself still needs the bridge re-pin ticket before this can be
  a pinned gate.
