# Plan: Networking Runtime

Status: feature request / design seed. Strategy locked 2026-06-19 (see below).

Goal: add a small target-neutral networking API without tying user code to
Linux syscall structs, libc, or ESP-IDF/lwIP details.

## Strategy (locked 2026-06-19) — twofold, two-layer

The networking effort is **twofold**, and the two parts stay deliberately
separate (different tools for different jobs):

1. **Own socket layer + primitives.** Async, syscall-first (no libc on Linux),
   ESP32-friendly (lwIP/IDF). This is the destination for async servers and the
   PXX-native API. Build it independently — it has no Synapse dependency.
2. **Compile Synapse** via its **Delphi-`Posix.*` path** (not its FPC/`BaseUnix`
   path), to reuse Synapse's higher-level clients (HTTP / FTP / SMTP / POP3 /
   DNS). This yields **blocking** clients (Synapse's `THTTPSend` etc. are welded
   to the blocking `TBlockSocket`), which is fine for one-shot client tasks but
   is **not** the async path. Do not expect to drive Synapse clients on the
   async reactor.

**Two API faces, one transport core.** Build the raw syscall socket ops once,
then expose two surfaces over them: (a) the PXX-native async API (part 1), and
(b) the `Posix.*` compatibility shape Synapse expects (part 2's shim). The shim
units map straight onto the same syscalls — so part-2 work reuses part-1's core.

### Layering

- **Protocols** (HTTP/FTP/SMTP/DNS parsing) — transport-agnostic; Synapse reuse
  candidate. Notably `synadns` (pure-Pascal DNS protocol over UDP) is reusable
  *independent* of the blocking question and fills the one real gap in
  syscall-only networking.
- **Transport** (sockets + multiplexing) — we own it: syscall + epoll-async on
  Linux (the reactor in `lib/rtl/asyncnet.pas`, already on all four targets),
  lwIP/IDF on ESP. Synapse's transport is blocking-only; that is the part we do
  **not** keep.

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

## Synapse Compatibility Target

Synapse should be the main Pascal library target for this feature. Do not vendor
it into the repository; use `tools/install_externals.sh` to clone the official
repository into `external/synapse/`.

Verified references:

- Official source repository: `https://github.com/geby/synapse`.
- The project moved from SourceForge to GitHub in January 2024.
- License is described by the project as modified BSD-style.
- Synapse is a Pascal TCP/IP and serial library for Delphi and Free Pascal.
- It primarily uses blocking/synchronous sockets and documents limited
  non-blocking mode.
- Feature surface includes TCP, UDP, DNS, IPv4/IPv6, proxies, ICMP/raw support,
  and optional SSL/TLS integrations.

Use Synapse in two ways:

- **Compatibility target:** compile minimal units first (`blcksock`, `synsock`,
  `synautil`) and record blockers by category: Pascal syntax, RTL/API,
  conditionals/directives, networking backend, and C/import dependency.
- **Standard-library direction:** model PXX's own `net.pas` API on the useful
  subset of Synapse, while keeping backend details private. A future PXX
  standard library may include a Synapse-compatible layer or a curated Synapse
  port under its own subfolder.

Non-blocking support is interesting for the async/coroutine roadmap, but it
should not drive the first milestone. Start with blocking loopback tests; later
audit Synapse's limited non-blocking paths against PXX async support.

### Reaching the Delphi-`Posix.*` path (the chosen route)

Synapse's Linux backend has two branches: the **FPC** branch (`{$ifdef FPC}` →
`synafpc` + `BaseUnix`/`Sockets`) and the **Delphi-POSIX** branch (gated on
Delphi platform defines → the `Posix.*` namespace). We target the Delphi-POSIX
branch because its surface is a small, well-bounded set of thin header units we
can back with our own syscalls.

The `Posix.*` units Synapse's posix path pulls in, and our mapping:

| Unit | Header | Contents | Our backing | Syscall-only? |
| --- | --- | --- | --- | --- |
| `Posix.SysSocket` | `<sys/socket.h>` | socket/bind/listen/accept/connect/send/recv/sendto/recvfrom/setsockopt/shutdown, `sockaddr`, `msghdr` | our socket syscalls | yes |
| `Posix.NetinetIn` | `<netinet/in.h>` | `sockaddr_in/in6`, `in_addr`, `htons`/`ntohs`/`htonl`/`ntohl`, `IPPROTO_*`, `INADDR_*` | pure structs + byte-swap | yes — no syscalls, just data |
| `Posix.SysSelect` | `<sys/select.h>` | `select`, `fd_set`, `FD_SET`/`ISSET`/`ZERO` | `select`/`pselect6` syscall | yes (but blocking — see below) |
| `Posix.SysTime` | `<sys/time.h>` | `timeval`, `gettimeofday` | `clock_gettime`/`gettimeofday` | yes |
| `Posix.StrOpts` | `<stropts.h>` | `ioctl` (Synapse uses `FIONBIO`) | `ioctl` syscall | yes |
| `Posix.Errno` | `<errno.h>` | `errno`, `EAGAIN`/`EWOULDBLOCK`/`EINTR`/`EINPROGRESS` | constant table + a mapping shim (our syscalls return `-errno`, no global) | yes |

So a **syscall-only Synapse is achievable** — only `SysSocket`/`SysSelect` need
real wrappers; `NetinetIn` is pure data; the rest are tiny. No libc.

### The two sharp edges (mind these)

1. **Define cheating + `mimic FPC`.** PXX predefines *neither* `FPC` nor the
   Delphi platform symbols (the `{$ifdef FPC}` = real-FPC landmine —
   [feedback_fpc_define_landmine]). So selecting the `Posix.*` branch is not just
   "define FPC": it is a **curated define profile** (feature-mimic-fpc) that (a)
   defines the Delphi-POSIX symbols so Synapse picks `Posix.*`, (b) steers around
   the `BaseUnix` branch, yet (c) still provides the `synafpc` shims the rest of
   Synapse expects. Expect a `{$ifdef FPC}` tangle that may need a tight profile
   or a small `synafpc`/include override. (Blocked on feature-directive-if-numeric
   → feature-mimic-fpc.)

2. **`{$mode delphi}`.** Synapse sets Delphi mode under FPC. PXX currently
   **swallows `{$mode ...}` as a no-op** (lexer.inc) and parses one objfpc-ish
   dialect — a *superset* of most Delphi syntax, so Synapse mostly parses. The
   one real divergence to watch is the **`@` operator**: Delphi defaults to
   *untyped* `@` (`{$T-}`) — `@proc`/`@var` yield a bare `Pointer` assignable
   anywhere — while objfpc is stricter. Verify PXX is permissive there (or teach
   PXX to recognise `{$mode delphi}` and relax `@` to untyped — cheaper than
   per-site fixes, folds into mimic-FPC). Other Delphi/objfpc differences (string
   base, `Result`, properties) do not bite; the only risk is a Delphi-only
   construct PXX lacks, which old-school Synapse mostly avoids.

### Build order for the Synapse goal

`feature-directive-if-numeric` → per-library **scoped manifest** delivering the
define set (`feature-dynamic-include-paths-config` "Per-library scoped
configuration" + `feature-mimic-fpc` for the set itself) → the `Posix.*` shim
(6 units over our syscalls) → `{$mode delphi}` `@`-relax knob → Synapse units
(`synautil`/`synaip`/`synsock`/`blcksock`, then clients). SSL (`ssl_openssl`)
deferred — pluggable, and blocking is acceptable there.

The Synapse define profile (`define POSIX/LINUX/UNIX`, `undef FPC`, `mode delphi`,
include path) lives in a per-directory manifest (e.g. `lib/synapse/pxxlib.cfg`)
applied ONLY to units under that folder — never viral to user code or sibling
libraries. `undef FPC` both selects Synapse's Delphi-Posix branch and dodges the
`{$ifdef FPC}`=real-FPC landmine, and being scoped it cannot leak. No CLI flags,
no Synapse source edits.

Manual inventory helper:

```sh
tools/install_externals.sh
test/manual/try_synapse_compile.sh
```

This is deliberately outside `make test`. It copies small smoke programs into
`external/synapse/` so PXX's current source-relative unit resolver can find the
Synapse units, then writes the full compiler log to `/tmp/pxx-synapse-compile.log`.

Current baseline from Synapse `f2e705b`:

- `synapse_smoke_synautil.pas`: fails on a conditional/directive parse issue.
- `synapse_smoke_synaip.pas`: fails on a conditional/directive parse issue
  while pulling `SysUtils, SynaUtil`.
- `synapse_smoke_synsock.pas`: reaches `synsock`, then fails resolving a unit
  source dependency.
- `synapse_smoke_blcksock.pas`: fails on a conditional/directive parse issue
  around the `uses` list / dependent units.

First investigation pass should classify these into directive support, unit
resolution, RTL unit availability, and Synapse platform-branch selection.

## First Milestone

Implement Linux syscall-only IPv4:

- TCP client with IP literal.
- TCP server with `SO_REUSEADDR`, `bind`, `listen`, `accept`.
- UDP `sendto` / `recvfrom`.
- Focused tests that avoid external network dependency where possible
  (loopback only).

DNS should be a later milestone, but it is **not** blocked on libc: DNS is just
UDP datagrams to port 53 (RFC 1035 wire format), and the nameserver comes from
`/etc/resolv.conf` (an `open`/`read`). So syscall-only DNS is achievable. Reuse
**Synapse's `synadns`** protocol logic (pure-Pascal query build + answer parse)
over our own UDP syscalls — that is the right reuse: the protocol, not a libc
binding. The same UDP code runs over lwIP on ESP32. Alternative: backend-provided
resolution via libc `getaddrinfo` / ESP-IDF where a libc dependency is acceptable.
