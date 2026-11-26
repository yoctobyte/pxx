---
slug: feature-crtl-the-libc-gaps-curl-found
track: C
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [crtl, nodisx]
summary: "What curl 8.23.0 + mbedTLS 3.6.8 needed from crtl: accept4 (curl's cf-socket.c), <linux/tcp.h> and the rest of Linux's TCP option numbers in <netinet/tcp.h> (TCP_FASTOPEN_CONNECT, ...). On 64-bit Linux it is the accept4 syscall (atomic flags, every family); elsewhere accept plus the two fcntl()s. Unknown flags are EINVAL. Test c_accept426 against gcc on loopback."
---
# The libc gaps curl found

- `accept4(fd, addr, len, flags)`: `lib/crtl/src/netinet/in.c`, declared in
  `<sys/socket.h>`. Where crtl already uses the raw socket syscalls
  (`__CRTL_RAW_SOCKADDR`: 64-bit Linux) it is `SYS_accept4`, so CLOEXEC and
  NONBLOCK are set atomically. Elsewhere it is `accept` followed by
  `fcntl(F_SETFD)` / `fcntl(F_SETFL)`: the flags end up set, but not
  atomically against a concurrent fork+exec.

- `<linux/tcp.h>`, which curl includes when configure finds it: it includes
  `<netinet/tcp.h>`, so the two cannot disagree. A plain build had silently
  used the host's copy; the strict check (`-nostdinc -I lib/crtl/include`)
  found eight units that needed it.
- `<netinet/tcp.h>` had TCP_NODELAY..TCP_KEEPCNT only. It now has Linux's
  whole list, 1..36, each value checked against the host's header. A missing
  option is not an error in code that tests `#ifdef TCP_X`: curl's
  TCP_FASTOPEN_CONNECT support was compiled out under pxx and in under gcc.

With those, all 590 units pass the strict header check.
