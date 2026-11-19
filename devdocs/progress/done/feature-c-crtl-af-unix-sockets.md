---
track: A
tags: [C]
prio: 30
type: feature
blocked-by: []
summary: "pxx's C runtime cannot do AF_UNIX sockets: bind/connect only take sockaddr_in (through __pxx_bind_ipv4/__pxx_connect_ipv4), socketpair is neither declared nor implemented, struct ucred is missing, and getsockopt only answers SO_ERROR. Found by Nilix, whose kernel now has AF_UNIX (stream, datagram, seqpacket, socketpair, SO_PEERCRED); its test user/nettest.c `unix` mode is refused by pxx (\"call to undeclared function: socketpair\")."
status: done
owner: pxx (Rainyday seat)
---

# AF_UNIX sockets in the C runtime

Nilix (`githome:nilix`, private) now implements AF_UNIX in its kernel. Its
user-side check, `user/nettest.c unix`, is plain POSIX C. gcc builds it and
it passes on Nilix. pxx refuses it:

    pascal26:128: error: call to undeclared function: socketpair

Even once it compiles, the runtime would fail it, because of these gaps in
lib/crtl:

- `bind`/`connect` take only `sockaddr_in`. They go through
  `__crtl_sockaddr_in` to `__pxx_bind_ipv4`/`__pxx_connect_ipv4`, so a
  `sockaddr_un` (a path, or an abstract name starting with NUL) gets
  EAFNOSUPPORT.
- `socketpair(2)` is missing from `<sys/socket.h>` and from the runtime.
- `struct ucred` (pid, uid, gid) is missing (glibc puts it behind
  `_GNU_SOURCE`, musl does not).
- `getsockopt` answers SO_ERROR alone, so SO_PEERCRED, SO_TYPE,
  SO_DOMAIN and SO_ACCEPTCONN are lost.
- `accept`/`getsockname`/`getpeername`/`recvfrom` presumably fill in
  `sockaddr_in` only.

Acceptance: `pascal26 user/nettest.c nettest` builds, and
`nettest unix` prints `unix: ok` on Linux and on Nilix. It covers
socketpair, EOF, EPIPE, a stream server on a path and on an abstract name,
and SO_PEERCRED. The gcc build is the reference.

How the PAL splits this, and what to do on ESP32, is pxx's call. On Linux,
AF_UNIX is ordinary socket syscalls with a different sockaddr.

## Progress 2026-11-15

- bind, connect, sendto, accept, recvfrom, getsockname and getpeername now
  pass any family but AF_INET straight to the kernel on 64-bit targets with
  the Linux call numbers (x86-64, aarch64), so a `sockaddr_un` works there.
  `test/c_crtl_sockaddr_families.c` (test-core) covers AF_UNIX, AF_INET6 and
  AF_NETLINK against gcc. `socketpair` exists on the same targets
  (`__CRTL_REAL_MSG`). i386 and the 32-bit embedded targets are unchanged.
- Still open: `struct ucred`, getsockopt beyond SO_ERROR (SO_PEERCRED,
  SO_TYPE, SO_DOMAIN, SO_ACCEPTCONN), and the nettest acceptance run.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).

## Done 2026-11-19

- getsockopt on 64-bit targets with the Linux call numbers (x86-64,
  aarch64) now asks the kernel for every option, as glibc does: SO_PEERCRED,
  SO_TYPE, SO_DOMAIN, SO_ACCEPTCONN and the rest. The other targets keep the
  PAL's SO_ERROR-only path. `struct ucred` was already in <sys/socket.h>.
- test/c_crtl_sockaddr_families.c checks SO_PEERCRED, SO_TYPE, SO_DOMAIN,
  SO_ACCEPTCONN and SO_ERROR on AF_UNIX against gcc, on x86-64 and aarch64.
- Acceptance: the pxx-built `nettest unix` (Rainyday's user/nettest.c)
  prints `unix: ok` on Linux and on the Rainyday kernel. Before, it got
  "hi from pid 0": SO_PEERCRED failed and left the struct unset.

Nilix is named Rainyday since 2026-11-18 (githome:rainyday).
