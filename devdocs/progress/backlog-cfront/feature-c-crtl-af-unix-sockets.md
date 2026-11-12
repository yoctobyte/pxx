---
track: A
tags: [C]
prio: 30
type: feature
blocked-by: []
summary: "pxx's C runtime cannot do AF_UNIX sockets: bind/connect only take sockaddr_in (through __pxx_bind_ipv4/__pxx_connect_ipv4), socketpair is neither declared nor implemented, struct ucred is missing, and getsockopt only answers SO_ERROR. Found by Gibux, whose kernel now has AF_UNIX (stream, datagram, seqpacket, socketpair, SO_PEERCRED); its test user/nettest.c `unix` mode is refused by pxx (\"call to undeclared function: socketpair\")."
status: open
owner: unassigned
---

# AF_UNIX sockets in the C runtime

Gibux (`githome:gibux`, private) now implements AF_UNIX in its kernel. Its
user-side check, `user/nettest.c unix`, is plain POSIX C. gcc builds it and
it passes on Gibux. pxx refuses it:

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
`nettest unix` prints `unix: ok` on Linux and on Gibux. It covers
socketpair, EOF, EPIPE, a stream server on a path and on an abstract name,
and SO_PEERCRED. The gcc build is the reference.

How the PAL splits this, and what to do on ESP32, is pxx's call. On Linux,
AF_UNIX is ordinary socket syscalls with a different sockaddr.
