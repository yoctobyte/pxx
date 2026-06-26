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

### Blocking vs async API decision (2026-06-21)

Expose two top-level networking libraries over the same PAL socket substrate:

```
PAL socket substrate
  socket/bind/connect/listen/accept/send/recv/shutdown/close
  nonblocking switch
  readiness wait/poll + portable error mapping (next PAL slice)
  no scheduler, no coroutine types, no protocol policy

net.pas
  normal blocking API
  TNetSocket, TNetAddress, Connect, Listen, Accept, Send, Recv, Close
  optional timeouts implemented with PAL readiness, not platform ifdefs

asyncnet.pas
  async/coroutine API
  AsyncConnect, AsyncAccept, AsyncRecv, AsyncSend
  depends on scheduler/reactor
  always uses nonblocking PAL sockets + readiness waits
```

Async is viral **above** the I/O boundary, not below it. The PAL must not know
about coroutines, promises, callbacks, scheduler tasks, or `RunUntilDone`; it
only exposes primitives that both blocking and async layers can use. The
blocking `net.pas` layer may either use blocking sockets directly or use
nonblocking sockets internally plus PAL readiness waits to implement timeouts.
The async layer always uses nonblocking sockets and parks/resumes through the
scheduler.

Protocol code should be factored so parsing/state machines are shared where
reasonable. The split happens at the byte transport boundary: blocking protocol
facades call `net.pas`; async protocol facades call `asyncnet.pas` and return
through the coroutine/async surface. Do not try to make Synapse's blocking
`TBlockSocket` drive the async reactor; it is a compatibility/protocol reuse
path, not the native async path.

### Layering — decision 2026-06-19 (refined: Posix.* is the canonical base)

`Posix.*` is the **canonical base API** (the clear, well-defined, stable C-header
surface). Everything else is a thin layer on top. The base has a **selectable
backend**, so the user chooses syscall vs libc:

```
        FPC-named units  (BaseUnix / Sockets / UnixType)   <- thin wrappers/aliases
        TNetSocket / TNetAddress  (portable async API)
                       |  both sit over v
                 Posix.*  (canonical API; one set of types, selectable impl)
        +--------------+----------------+
   posix_syscall   posix_libc     posix_lwip (ESP)         <- selectable backend
        +--------- shared types/structs (one include) -----+
```

- **`Posix.*` base, two (later three) interchangeable backends.** Same interface;
  pick one per build via the scoped manifest / a define. **Default = syscall**
  (the project goal — "just works" means syscall); **`define PXX_POSIX_LIBC`**
  flips to the libc backend (a fallback for the genuinely-hard-without-libc bits,
  or for users who just want to link libc and move on).
- **"Twice" is ~1.3x, not 2x.** The types/structs (`sockaddr_in`, `fd_set`,
  constants — `Posix.NetinetIn` is pure data) live in ONE shared include, used by
  both backends. Only the function bodies differ: the syscall impl (the meaty one
  we want anyway) vs the libc impl (just `external` bindings — trivial).
- **FPC-named units wrap `Posix.*`.** `BaseUnix`/`Sockets`/`UnixType` are thin
  aliases over the base — implemented once, not a second socket binding. Needed
  for the own-RTL strategy + the eventual compile-FPC-source goal. So the
  master question is settled: **`Posix.*` is master; FPC names wrap it.**
- Compatibility reaches **left or right**: Synapse's Delphi-Posix branch consumes
  `Posix.*` directly; its FPC branch consumes the FPC wrappers; the per-library
  scoped manifest selects which branch each library compiles against.

**ESP32 (the seam moved — softer than before).** lwIP exposes a **BSD-socket API**
(`socket`/`bind`/`connect`/`select`) that is essentially Posix-shaped, so a third
backend **`posix_lwip`** is plausible — meaning `Posix.*` and the FPC wrappers can
reach ESP too, with documented gaps (lwIP's limited `select`/`poll`, no
Unix-domain sockets, no `/proc`). The seam is now "backend differs", not "API
absent". The fully portable cross-target surface remains **`TNetSocket`**; the
async path stays the epoll-coroutine reactor (Posix.*/FPC are blocking/`select`-
shaped compat surfaces — they coexist with the async transport, they do not merge).

### Linux network config via `/proc` and `/sys` (syscall-only)

Network introspection on Linux needs no libc/ioctl: read `/proc` and `/sys` as
plain files (`open`/`read` syscalls). Sources: `/etc/resolv.conf` (nameservers),
`/proc/net/route` (routing), `/proc/net/dev` (interface stats), `/proc/net/tcp`
+ `/proc/net/udp` (live sockets), `/sys/class/net/*` (interfaces, MAC, MTU,
up/down). Prefer these over `ioctl(SIOCGIF*)` where possible — pure reads, no
binding surface.

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

Synapse's Linux/Unix backend actually has **three** branches: the **FPC** branch
(`{$ifdef FPC}` → `synafpc` + `BaseUnix`/`Sockets`), the legacy **Kylix** branch
(Borland Kylix 2001–2003, dead — its monolithic `Libc` unit, `uses libc`), and
the modern **Delphi-POSIX** branch (the `Posix.*` namespace). Do not confuse the
last two: `Posix.*` is **current Embarcadero Delphi** — introduced in Delphi XE2
(2011) for the cross-platform LLVM compilers, still the POSIX RTL in Delphi 12
today (Linux64 via `DCCLinux64`, macOS/iOS/Android). On real Delphi these units
are thin **libc** import bindings; we provide the *same API surface* backed by
**syscalls** instead — the caller (Synapse) cannot tell the difference.

We target the Delphi-`Posix.*` branch because its surface is a small,
well-bounded set of thin header units (only the six below — Synapse does not pull
the whole `Posix.*` RTL). The scoped manifest's `undef FPC` + Delphi-platform
defines steer **away from both** the FPC/`BaseUnix` branch and the dead
Kylix/`libc` branch, onto the modern `Posix.*` one. (Earlier ticket notes about
PXX "picking the Kylix path" describe the *bug* we are steering out of.)

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
configuration" + `feature-mimic-fpc` for the set itself) → dotted/namespace unit
names (`feature-dotted-unit-names`) → `{$IF DECLARED(...)}` support
(`feature-conditional-declared-directive`) → the `Posix.*` shim (6 units over
our syscalls) → `{$mode delphi}` `@`-relax knob → Synapse units
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
SYNAPSE_PROFILE=posix test/manual/try_synapse_compile.sh
```

This is deliberately outside `make test`. It copies small smoke programs into
`external/synapse/` so PXX's current source-relative unit resolver can find the
Synapse units, then writes the full compiler log to `/tmp/pxx-synapse-compile.log`.
By default the helper uses `stable_linux_amd64/default/pinned`; `COMPILER` or
`PXX_STABLE` can override it. `SYNAPSE_PROFILE=posix` is only a manual stand-in
for the future scoped library manifest: it defines the Delphi/POSIX symbols
needed to steer Synapse toward the `Posix.*` branch. It is not a replacement for
the manifest feature and should not become a source edit.

Current baseline from Synapse `f2e705b`, pinned stable compiler, 2026-06-21:

- Default profile:
  - `synapse_smoke_synautil.pas`: `uses: unit source not found: libc`.
  - `synapse_smoke_synaip.pas`: `uses: unit source not found: libc`.
  - `synapse_smoke_synsock.pas`: `uses: unit source not found: system`.
  - `synapse_smoke_blcksock.pas`: `uses: unit source not found: system`.
- POSIX-cheat profile:
  - `synapse_smoke_synautil.pas`: `uses: unit source not found: posix` from
    dotted unit truncation (`Posix.*` parsed as `posix`).
  - `synapse_smoke_synaip.pas`: same `posix` dotted-unit blocker.
  - `synapse_smoke_synsock.pas`: `conditional directive: expected operator` at
    `{$IF DECLARED(Posix.StrOpts.FIONREAD)}` in `ssposix.inc`.
  - `synapse_smoke_blcksock.pas`: `uses: unit source not found: system`, likely
    the same dotted-unit-name class for `System.Generics.*`.

First investigation pass should classify these into directive support, unit
resolution, RTL unit availability, and Synapse platform-branch selection.

## First Milestone

Implement Linux syscall-only IPv4:

- TCP client with IP literal.
- TCP server with `SO_REUSEADDR`, `bind`, `listen`, `accept`.
- UDP `sendto` / `recvfrom`.
- Focused tests that avoid external network dependency where possible
  (loopback only).

DNS should be a later milestone tracked in
`feature-dns-resolver-library`. It is **not** blocked on libc: DNS is just UDP
datagrams to port 53 (RFC 1035 wire format), and the nameserver usually comes
from `/etc/resolv.conf` (an `open`/`read`). So syscall-only DNS is achievable.
The planned `dns.pas` facade has selectable resolver backends:

- `dns_libc`: `getaddrinfo` / `freeaddrinfo`; most compatible with host NSS and
  resolver policy, but external-libc and blocking.
- `dns_wire`: pure Pascal DNS client over PAL UDP/TCP; supports blocking and
  async facades over shared packet/parser code; reads `/etc/hosts` and
  `/etc/resolv.conf`; no public DNS fallback by default.
- `dns_resolved`: systemd-resolved over a minimal D-Bus client; Linux/systemd
  only, but can preserve split-DNS/VPN policy without libc.
- `dns_esp`: ESP-IDF/lwIP resolver API backend if validated, otherwise use
  `dns_wire` over lwIP UDP after network bring-up.

Backend selection is deployment policy, not language semantics. Prefer the
project/profile config mechanism long term (`dns_backend = wire|libc|resolved|
esp|auto|auto_fallback`, `dns_public_fallback = false`), with temporary defines
acceptable for early slices. Runtime fallback should be opt-in because each
backend can honor different DNS policy. Public fallback servers such as
`1.1.1.1` or `8.8.8.8` must be opt-in only; defaulting to them breaks VPNs,
private LANs, split DNS, captive portals, enterprise policy, and privacy
expectations.

Two pure-Pascal references, both FPC-named-or-portable:

- **FPC's `netdb`** — resolves in pure Pascal already (reads `/etc/resolv.conf` +
  `/etc/hosts`, sends its own DNS queries, no libc `getaddrinfo`). Syscall-shaped
  and matches our naming — the closest model.
- **Synapse's `synadns`** — pure-Pascal query build + answer parse, reusable
  independent of Synapse's blocking transport.

Port one over our UDP syscalls; the same UDP code runs over lwIP on ESP32.
Alternative: backend-provided resolution via libc `getaddrinfo` / ESP-IDF where a
libc dependency is acceptable.
