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
