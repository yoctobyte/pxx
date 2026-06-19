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

Full design lives in `docs/developer/plan-networking.md`. Key decisions:

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
| Conditional/directive parsing | Synapse smoke tests all fail on directive issues |
| Unit resolution from source paths | `synsock` fails resolving a unit dependency |
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
| `synautil` | directive parse fail | conditional/directive |
| `synaip` | directive parse fail (pulls SysUtils) | directive + RTL |
| `synsock` | unit resolution fail | resolver / path |
| `blcksock` | directive parse fail (uses list) | directive + RTL |

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

DNS deferred to a later milestone.

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
