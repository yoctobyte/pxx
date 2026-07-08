---
prio: 45
---

# crtl: missing <netinet/tcp.h>, <netdb.h>, <poll.h> — ENet falls back to host headers

- **Type:** feature (crtl header surface). Track C.
- **Found:** 2026-07-08 game-library ladder, ENet probe
  (feature-game-library-candidate-suite).

## Symptom
ENet's `unix.c` includes `<netinet/tcp.h>`, `<netdb.h>`, `<poll.h>` — none in
`lib/crtl/include`, so the host copies are pulled, dragging a full host socket
header set that redefines crtl's own `struct in_addr` and triggers
bug-c-tag-redef-misfiles-field-selfref-segv.

## Ask
Add minimal crtl headers: `netinet/tcp.h` (TCP_NODELAY + struct tcphdr subset),
`netdb.h` (struct hostent/addrinfo + gethostby*/getaddrinfo decls — impls can
be the not-found stubs already in socket.c), `poll.h` (struct pollfd, POLLIN/
POLLOUT, poll() over the PAL select/poll bridge). Also missing impls surfaced:
`sendmsg`/`recvmsg` (unix.c uses them for scatter-gather I/O).

## Gate
ENet unity compiles against crtl only (no host header fallback); enet_probe
links + runs (after the tag-redef segv is fixed too).
