---
prio: 45  # auto
---

# Networking runtime

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-07 (manual request, consolidates plan-networking.md)

## Summary

Add a target-neutral networking API (`net.pas`) with platform-specific backends.
Use the Synapse library as both a compiler compatibility target and correctness
test suite.

## Design Reference

Full design lives in `devdocs/developer/plan-networking.md`. Key decisions:

- **Public API:** `TNetSocket`, `TNetAddress`, `Connect`, `Listen`, `Accept`,
  `Send`/`Recv`, `Close`. Later: `Poll`, TLS hooks, async integration.
- **Three backends:**
  - `net_linux_sys.pas` — raw Linux x86-64 syscalls, no libc.
  - `net_posix.pas` — libc sockets + `getaddrinfo`.
  - `net_esp32.pas` — ESP-IDF/lwIP sockets.
- **Abstraction strategy:** syscall preferred on Linux, library on ESP32.
  Backend selection at compile time via target conditionals.

## Analysis: Work Required

### 1. Compiler prerequisites (may already be in progress)

| Blocker | Notes |
|---------|-------|
| Conditional/directive parsing | POSIX-profile Synapse hits missing `{$IF DECLARED(...)}` support |
| Unit resolution from source paths | Dotted units such as `Posix.SysSocket` truncate to `posix` |
| RTL unit availability | `SysUtils`, `Classes` stubs or equivalents needed |
| Platform-branch selection | `{$IFDEF LINUX}` / `{$IFDEF FPC}` handling |

### 2. Runtime implementation order

1. Syscall constants + `sockaddr_in` struct layout for Linux x86-64.
2. Byte-order helpers (`htons`, `ntohs`, `htonl`, `ntohl`).
3. Thin syscall wrappers: `socket`, `bind`, `listen`, `accept`, `connect`,
   `read`/`write`, `sendto`/`recvfrom`, `close`, `setsockopt`.
4. Public `net.pas` API wrapping the above.
5. Loopback tests: TCP echo client/server, UDP send/recv.

### 3. Synapse compatibility milestones

| Unit | Current state | Likely fix category |
|------|--------------|---------------------|
| `synautil` | default: missing `libc`; POSIX profile: missing `posix` | branch selection + dotted units |
| `synaip` | default: missing `libc`; POSIX profile: missing `posix` | branch selection + dotted units |
| `synsock` | default: missing `system`; POSIX profile: `{$IF DECLARED(...)}` parse fail | branch selection + directive support |
| `blcksock` | default: missing `system`; POSIX profile: missing `system` | dotted units / later RTL availability |

First pass: classify failures. Second pass: fix compiler blockers. Third pass:
compile units successfully.

### 4. Test strategy

- Loopback-only tests (no external network dependency).
- Synapse smoke scripts already exist: `test/manual/try_synapse_compile.sh`.
- Add automated `make test` targets once basic compilation works.

## First Milestone

Linux syscall-only IPv4:
- TCP client with IP literal.
- TCP server with `SO_REUSEADDR`, `bind`, `listen`, `accept`.
- UDP `sendto` / `recvfrom`.
- Loopback tests only.

DNS deferred to `feature-dns-resolver-library`.

## Log

- 2026-06-07 — ticket opened; consolidated from user note and plan-networking.md.
- 2026-06-10 — relative-path units delivered (4aa293a); improved uses error now shows the synsock failure is a missing `syncobjs` RTL unit, i.e. RTL availability, not path resolution. Other three smoke units still fail on conditional-directive parse.
- 2026-06-10 — quick-win pass (440a9e0, f81ea83): syncobjs RTL stub added;
  directive layer now digests jedi.inc fully (inactive-branch `{$IF}` eval
  skipped per FPC semantics, `{$IFOPT}` recognized, `{$IFEND}` accepted,
  define table 128→1024). All four smoke units now fail on ONE remaining
  blocker class: platform-branch selection. PXX predefines LINUX but not FPC,
  so jedi.inc picks the Kylix path (`uses libc`/`system`). Predefining FPC
  globally would break self-host (compiler source uses `{$ifdef FPC}` to mean
  "real FPC, not PXX") — needs a design decision (per-source define set, or a
  PXX-aware branch in install step, or `-d FPC` only for foreign code). After
  that: RTL availability (synafpc, termio, sockets, netdb, Classes surface).
- 2026-06-10 — platform-branch decision made: opt-in mimic mode, see feature-mimic-fpc (35345a3). Synapse compatibility milestones wait on it; the syscall net.pas milestone does not.
- 2026-06-16 — the syscall net.pas milestone has a concrete start: `lib/rtl/asyncnet.pas` — an **async** TCP socket layer (TcpListen/Accept/Connect/Recv/Send/Close) over the coroutine epoll reactor (feature-async-coroutines), x86-64, raw Linux syscalls, no libc. Proven by `test/test_asyncecho.pas` (concurrent echo server). Not yet the target-neutral `TNetSocket`/`TNetAddress` API or the cross/esp32 backends; asyncnet is the Linux-x86-64 async backend the abstraction will wrap. Cross-target parity tracked in feature-cross-target-feature-parity.
- 2026-06-19 — **strategy locked twofold** (see plan-networking.md "Strategy"
  section). (1) Own async/syscall/ESP socket layer — the `asyncnet.pas` reactor
  is its Linux-x86-64 start; build the target-neutral `TNetSocket`/`TNetAddress`
  + cross/esp32 backends independently of Synapse. (2) Compile Synapse via its
  **Delphi-`Posix.*`** path (not the FPC/BaseUnix path) to reuse its HTTP/FTP/
  SMTP/POP3/DNS clients — yields BLOCKING clients (welded to `TBlockSocket`),
  good for one-shot client tasks, not async. Build one transport core, expose two
  faces (native async API + `Posix.*` compat shim). The `Posix.*` shim is 6 thin
  units over our syscalls (`SysSocket`/`SysSelect`/`SysTime`/`StrOpts`/`Errno` +
  pure-data `NetinetIn`) — syscall-only achievable, no libc. **DNS** is not
  libc-blocked: reuse Synapse `synadns` (UDP/RFC1035) over our UDP syscalls,
  nameserver from `/etc/resolv.conf`. Synapse goal depends on feature-mimic-fpc
  (curated define profile to select `Posix.*`) + `{$mode delphi}` handling (mainly
  relax `@` to untyped). SSL deferred (pluggable `ssl_openssl`, blocking ok).
- 2026-06-19 — **dual-facade decision.** Expose BOTH naming layers as thin
  facades over one private syscall transport core (siblings, neither calls the
  other): (2) FPC-native `BaseUnix`/`Sockets`/`UnixType` — built anyway for
  own-RTL + compile-FPC-source, and FPC's own versions are already syscall-based;
  (3) `Posix.*` — the clear C-header surface (libc-backed on real Delphi,
  syscall-backed here). The scoped manifest picks which branch each library
  compiles against → reach compat "left or right". If ever collapsing to one
  master, FPC-native is master (Posix.* wraps it). **ESP caveat:** `Posix.*` is
  Unix-only (no ESP); the portable layer is `TNetSocket`, with Posix.*/FPC-native
  as Unix porting facades. DNS: FPC `netdb` (pure-Pascal resolver, syscall-shaped)
  joins `synadns` as a reference. Linux net config via `/proc`+`/sys` reads (no
  libc/ioctl). FPC RTL itself is largely libc-free — validates the syscall model.
- 2026-06-19 — **layering refined: `Posix.*` is the canonical base; FPC wraps it.**
  Posix.* base API has a SELECTABLE backend — `posix_syscall` (default, "just
  works") and `posix_libc` (opt-in via `define PXX_POSIX_LIBC`), same interface so
  the user picks syscall vs libc. Cost is ~1.3x not 2x: types/structs shared in one
  include (NetinetIn is pure data), only function bodies differ (syscall = the meaty
  impl we want; libc = trivial externs). FPC-named units (BaseUnix/Sockets/UnixType)
  are thin wrappers OVER Posix.* (master question settled: Posix is master). ESP seam
  softened: lwIP's BSD-socket API is Posix-shaped, so a 3rd backend `posix_lwip` lets
  Posix.*/FPC reach ESP with documented gaps — "backend differs", not "API absent".
  Portable cross surface stays TNetSocket; async stays the epoll reactor (Posix/FPC
  are blocking compat surfaces, coexist not merge).
- 2026-06-21 — PAL network foundation landed under
  `feature-platform-abstraction-layer`: IPv4 TCP primitives in `platform.pas`
  with POSIX raw-syscall backend and ESP-IDF/lwIP object-shape backend. Regression
  `test/lib_platform_net.pas` proves POSIX loopback TCP; native `--platform=esp`
  tests assert no host fallback; C3/S3 object smokes import the expected `lwip_*`
  symbols. Remaining PAL networking gaps (UDP, poll/select readiness, exact errno,
  ESP-IDF run validation, IPv6/DNS hooks) are split to
  `feature-pal-network-datagram-poll-errno`.
- 2026-06-21 — Blocking/async layering decision documented in
  `devdocs/developer/plan-networking.md`: keep one PAL socket substrate, then expose
  two top-level libraries above it. `net.pas` is the normal blocking API;
  `asyncnet.pas` is coroutine-backed and viral by design. PAL must stay scheduler-
  free and provide only socket ops, nonblocking mode, readiness/error primitives,
  and portable capabilities.
- 2026-06-21 — Synapse support audit continued against the pinned stable
  compiler with the manual smoke helper. `test/manual/try_synapse_compile.sh`
  now defaults to `stable_linux_amd64/default/pinned` and has
  `SYNAPSE_PROFILE=posix` as a temporary stand-in for the future scoped manifest.
  Default profile still falls into the wrong/missing branch (`libc`/`system`).
  The POSIX profile exposes two compiler blockers before the library/PAL shims
  can matter: dotted namespace unit names (`Posix.*`, `System.Generics.*`) and
  `{$IF DECLARED(Qualified.Symbol)}`. Filed `feature-dotted-unit-names` and
  `feature-conditional-declared-directive`; no Synapse source workaround.
- 2026-06-21 — DNS resolver policy split out to
  `feature-dns-resolver-library`: `dns.pas` facade with selectable `dns_libc`
  (`getaddrinfo`), `dns_wire` (pure Pascal over PAL UDP/TCP), and `dns_resolved`
  (systemd-resolved over D-Bus) backends. Public DNS fallback is explicit opt-in
  only, never default.
- 2026-06-22 — PAL socket substrate is now complete enough for the blocking
  `net.pas` first milestone (Track B, stable v37). On top of the TCP primitives
  it now provides: UDP `PalSendToIpv4`/`PalRecvFromIpv4` with peer reporting,
  `PalPoll` readiness (raw ppoll), `-errno` returns plus
  `PAL_NET_EWOULDBLOCK`/`ECONNREFUSED`/`ECONNRESET`
  (`feature-pal-network-datagram-poll-errno`, done), and socket introspection
  `PalGetSockError` (SO_ERROR), `PalGetSockNameIpv4`, peer-reporting
  `PalAcceptIpv4` (commit adebdf9). All host-proven on loopback via
  `lib_platform_net*` in `make lib-test`. The PAL stays scheduler-free; remaining
  net.pas work is the target-neutral `TNetSocket`/`TNetAddress` blocking API over
  these primitives — no new PAL surface expected for IPv4 loopback TCP/UDP. Still
  PAL-blocked above IPv4: IPv6 sockaddr layout (`PAL_NET_AF_INET6` + 28-byte
  sockaddr_in6 fill/parse) — to be added when net.pas reaches it.
- 2026-06-22 — **First-milestone `lib/rtl/net.pas` landed** (Track B, stable v37,
  commit 3d7ac46): the blocking IPv4 face the milestone called for, with no
  platform conditionals of its own. `TNetSocket`/`TNetAddress`; TCP
  `NetTcpListen`/`NetTcpAccept` (peer-reporting)/`NetTcpConnect`/`NetSend`/
  `NetRecv`; UDP `NetUdpBind`/`NetUdpSendTo`/`NetUdpRecvFrom`; plus
  `NetGetSockName`/`NetGetSockError`/`NetShutdown`/`NetClose`. End-to-end
  loopback proof in `test/lib_net.pas` (single thread: blocking connect completes
  via the kernel backlog, then accept; TCP echo + UDP roundtrip + ephemeral
  bind/getsockname + peer address) wired into `make lib-test`. `asyncnet.pas`
  stays the coroutine face over the same PAL primitives. STILL OPEN under this
  ticket: IPv6, DNS (`feature-dns-resolver-library`), the Synapse / `Posix.*`
  compat path (Track A blockers `feature-dotted-unit-names` +
  `feature-conditional-declared-directive`), and async/blocking facade
  unification.
