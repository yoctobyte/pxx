# Plan: Networking Runtime

Status: feature request / design seed.

Goal: add a small target-neutral networking API without tying user code to
Linux syscall structs, libc, or ESP-IDF/lwIP details.

## Public API Shape

Start with a Pascal unit such as `net.pas`:

- `TNetSocket`
- `TNetAddress`
- `Connect(host, port)`
- `Listen(address, port)`
- `Accept`
- `Send` / `Recv`
- `Close`
- later: `Poll`, TLS hooks, async integration

Keep DNS and address representation backend-owned. User code should not care
whether resolution came from Linux syscalls, libc `getaddrinfo`, or ESP-IDF.

## Backends

- `net_linux_sys.pas`: Linux x86-64 syscalls only. Supports IP literals first;
  no libc dependency. Needs syscall constants, `sockaddr_in`/`sockaddr_in6`
  layout, byte-order helpers, and wrappers for `socket`, `bind`, `listen`,
  `accept`, `connect`, `read`/`write` or `sendto`/`recvfrom`, `close`,
  `setsockopt`, and maybe `poll`.
- `net_posix.pas`: libc/POSIX backend. Uses imported headers or direct externals
  for sockets plus `getaddrinfo`, `freeaddrinfo`, `inet_pton`, `inet_ntop`.
  Easier DNS and IPv6, but generated programs depend on libc.
- `net_esp32.pas`: ESP-IDF/lwIP sockets. Socket API is C-library backed. Keep
  WiFi/network-interface bring-up separate, e.g. `netif_esp32.pas`.

## First Milestone

Implement Linux syscall-only IPv4:

- TCP client with IP literal.
- TCP server with `SO_REUSEADDR`, `bind`, `listen`, `accept`.
- UDP `sendto` / `recvfrom`.
- Focused tests that avoid external network dependency where possible
  (loopback only).

DNS should be a later milestone. Options: small UDP resolver over configured
nameservers, or backend-provided resolution via libc/ESP-IDF.
