---
prio: 60  # auto
---

# DNS resolver library (`dns.pas`) with selectable backends

- **Type:** feature (Track B networking / resolver policy)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21 (DNS design discussion)
- **Relation:** follows `feature-pal-network-datagram-poll-errno`; feeds
  `feature-networking`, `asyncnet.pas`, and Synapse/protocol reuse

## Summary

Add a stable `dns.pas` resolver facade with multiple selectable resolver
backends. DNS resolution is policy above PAL, not a PAL primitive: PAL should
only provide file IO, UDP/TCP sockets, readiness/error primitives, and later
AF_UNIX if D-Bus needs it.

The project should support all three main paths:

1. `getaddrinfo()` via libc for maximum system compatibility.
2. A pure Pascal DNS wire client over PAL UDP/TCP for libc-free executables.
3. systemd-resolved over D-Bus for Linux systems that want systemd split-DNS and
   resolver policy without linking libc.

## Public shape

`dns.pas` should be the stable facade:

```text
lib/rtl/dns.pas
  public API
  TDnsAddress, TDnsResult, TDnsOptions
  ResolveHost, ResolveService
  async variants later, or a sibling async facade over the same core
```

Keep protocol parsing/state separate from transport:

```text
dns_wire_core
  DNS packet encode/decode
  answer parser
  CNAME chain handling
  cache structs later
  /etc/hosts and resolv.conf parser for POSIX

dns_wire_blocking
  uses net.pas / blocking PAL sockets

dns_wire_async
  uses asyncnet.pas / nonblocking PAL sockets + readiness waits
```

The split mirrors the larger networking decision: blocking and async are
different facades above the IO boundary, but the DNS packet/parser core should
be shared.

## Resolver backends

### `dns_libc`

Use `getaddrinfo()` / `freeaddrinfo()`.

Pros:

- Best system compatibility.
- Honors NSS policy, `/etc/nsswitch.conf`, `/etc/hosts`, mDNS/LDAP plugins,
  system resolver quirks, `AI_ADDRCONFIG`, IDN behavior where libc supports it.
- Good explicit compatibility backend for hosted POSIX programs.

Cons:

- External libc dependency.
- Blocking API shape unless wrapped in a thread or otherwise isolated.
- Not the default path for libc-free executables.

### `dns_wire`

Pure Pascal DNS client over PAL UDP/TCP.

Baseline behavior:

- Read `/etc/hosts`.
- Read `/etc/resolv.conf`.
- Use only configured nameservers by default.
- No public DNS fallback by default.
- UDP first.
- TCP fallback when a UDP response is truncated.
- Clear failure if no resolver configuration exists.

Policy work to implement deliberately:

- `search` domains.
- `ndots`.
- multiple nameservers.
- timeout and retry behavior.
- A/AAAA query ordering and IPv4/IPv6 preferences.
- CNAME chains.
- negative responses.
- EDNS0 later, not first slice.

Pros:

- Portable and libc-free.
- Works for both blocking and async because the transport is under our control.
- Small enough to implement and test as a real library.
- Can run over POSIX PAL sockets and ESP/lwIP sockets once UDP exists.

Cons:

- Does not automatically honor full NSS, mDNS, LDAP, per-link VPN split DNS, or
  desktop resolver policy.
- Correct resolver policy is more work than the DNS packet format itself.

### `dns_resolved`

Talk to systemd-resolved over D-Bus.

Pros:

- Can honor systemd-resolved policy: split DNS, per-link routing domains, VPN
  DNS, DNSSEC policy, LLMNR/mDNS policy, and the local resolved cache.
- Can be libc-free if the minimal D-Bus client is implemented directly over the
  system bus socket.

Cons:

- Linux/systemd only.
- Requires systemd-resolved to be present and reachable.
- Requires AF_UNIX support and a minimal D-Bus wrapper.
- Not portable enough to be the default backend.

### `dns_esp`

ESP-IDF/lwIP resolver API backend, if platform DNS is already configured by the
ESP network stack.

Pros:

- Uses the platform's configured DNS state after WiFi/netif bring-up.
- Likely the right default for ESP hosted/IDF apps if lwIP resolver APIs are
  available and tested.

Cons:

- ESP-specific.
- Still needs clear behavior when network interface bring-up has not happened.
- If the API shape is blocking, async callers should prefer `dns_wire_async`
  over PAL/lwIP UDP where possible.

### Low-priority experimental: `dns_libc_dyn`

Dynamic-loading libc (`dlopen` + `getaddrinfo`) is technically possible as an
explicit experimental backend, but should not drive the design:

- It is still libc-dependent.
- It is Linux/glibc-shaped.
- ABI/type details are easy to get wrong.
- It weakens the clarity of "library-less executable".

Static backend selection is cleaner.

## Backend selection

Resolver choice is deployment policy, not language semantics. Prefer project or
library profile configuration over a long-term language-level compiler switch.
A compiler define/switch is acceptable as a first crude mechanism, but the final
shape should fit the scoped profile/config system:

```text
dns_backend = wire
dns_backend = libc
dns_backend = resolved
dns_backend = esp
dns_backend = auto
dns_backend = auto_fallback
dns_public_fallback = false
```

Possible define names for the early slice:

```text
PXX_DNS_WIRE
PXX_DNS_LIBC
PXX_DNS_RESOLVED
PXX_DNS_ESP
```

`auto` should mean compile/profile-time choice based on target and enabled
features. It should not silently change DNS policy at runtime.

`auto_fallback` should be explicit and runtime-ordered, for example:

```text
resolved -> wire
esp -> wire
libc -> wire
```

Runtime fallback is useful but can surprise users because each resolver path may
honor different DNS policy. It must be opt-in.

Public DNS fallback servers (`1.1.1.1`, `8.8.8.8`, etc.) must be opt-in only and
off by default. Defaulting to public resolvers breaks VPNs, private LAN names,
split DNS, captive portals, enterprise policy, and privacy expectations.

## Recommended defaults

- Linux/POSIX libc-free profile: `dns_wire`.
- Linux/systemd profile: `dns_resolved`, with optional explicit fallback to
  `dns_wire`.
- Hosted compatibility profile: `dns_libc`.
- ESP-IDF profile: `dns_esp` if the lwIP/IDF resolver API is validated; otherwise
  `dns_wire` over PAL/lwIP UDP after network bring-up.
- Async profile: `dns_wire_async` by default. `dns_libc` and `dns_resolved` can
  be exposed to async code only through an explicit blocking-isolation strategy.

## Overlooked or adjacent options

- `/etc/nsswitch.conf` is not a separate backend, but it matters. A pure wire
  resolver should at least implement `files dns` behavior (`/etc/hosts` then DNS)
  and document that full NSS compatibility belongs to `dns_libc`.
- mDNS and LLMNR are separate local-name protocols. They are not baseline DNS.
  `dns_resolved` may cover them through system policy; `dns_wire` should not grow
  them in the first slice.
- DoH/DoT are useful future explicit application-policy backends, not system
  resolver replacements.
- c-ares or another C resolver library is a possible external-library backend,
  but less compelling than either `dns_libc` for system compatibility or
  `dns_wire` for libc-free output.

## Acceptance

- `dns.pas` exposes a backend-neutral resolver API for host/service lookup.
- At least one backend is selected by profile/define without platform conditionals
  leaking into user code.
- `dns_wire` reads `/etc/hosts` and `/etc/resolv.conf`, uses configured
  nameservers, and never falls back to public DNS unless explicitly enabled.
- Blocking and async DNS share packet/parser code where practical.
- Documentation states the compatibility tradeoff: `dns_libc` is system-correct
  but external/blocking; `dns_wire` is libc-free but implements only our resolver
  policy; `dns_resolved` is systemd-specific but can preserve split-DNS policy
  without libc.

## Log

- 2026-06-21 — design filed. Decision: take all three serious paths (`libc`,
  pure wire DNS, systemd-resolved/D-Bus), make the resolver backend selectable,
  and never default to public DNS fallback.
- 2026-06-22 — **first slice landed: `lib/rtl/dns_wire_core.pas`** (Track B,
  stable v37, commit a3d97d9). Transport-free packet codec — the shared
  `dns_wire_core` from the design's split. `DnsBuildQueryA` encodes a recursive
  A query; `DnsParseResponseA` walks answer RRs (handling 0xC0 compressed names)
  and extracts A records as host-order IPv4, returning the DNS RCODE or a
  negative `DNS_ERR_*`. Pure/offline: `test/lib_dns_wire.pas` checks the query
  wire bytes and parses a canned 2-answer response; FPC-oracle verified
  (byte-identical); wired into `make lib-test`. NEXT slices: AAAA, CNAME-chain
  following, `/etc/hosts` + `/etc/resolv.conf` parse, then `dns_wire_blocking`
  over `net.pas` (UDP query + TCP-truncation fallback) and `dns_wire_async`
  over `asyncnet.pas`. The `dns.pas` facade + backend selection come after a
  backend works end to end.
- 2026-06-22 — **config baseline + working dns_wire backend landed** (Track B,
  stable v38):
  - `lib/rtl/dns_config.pas` (commits e4c3916 + earlier): `DnsParseIpv4`
    (strict dotted-quad), `DnsParseResolvConf` (nameserver extraction), and
    `DnsLookupHosts` (the "files" half of "files dns" — case-insensitive
    hostname/alias match over `/etc/hosts` text). Pure/offline, FPC-oracle
    verified, in `make lib-test`.
  - `lib/rtl/dns_wire_blocking.pas` (commit 791fa1e): `DnsResolveA` — UDP A
    query to a caller-supplied nameserver over PAL (build -> sendto -> PalPoll
    -> recvfrom -> parse -> id check -> extract). No resolver policy, no public
    DNS assumption. Proven end to end by `test/lib_dns_resolve.pas`: a **forked**
    mock DNS server (process, not thread; both sides timeout-bounded) serves the
    real query with a canned response echoing the query id; rcode=0, 2 IPs,
    8/8 stable. The whole stack is written var->var-forwarding-free so it stays
    correct on riscv32.
  REMAINING: multi-nameserver retry, TCP fallback on a truncated (TC) response,
  search/ndots qualification, per-query id randomization, AAAA; then the
  `dns.pas` facade + backend selection (`dns_libc`, `dns_resolved`, `dns_esp`)
  and an async sibling over `asyncnet.pas`. Live-network resolution stays
  untested by policy (loopback/mock only; configured nameservers, never public).
- 2026-06-22 — **`lib/rtl/dns.pas` facade landed** (commit 1a71354): the stable
  "files dns" entrypoint. `DnsResolveHostEx(hostsText, ns, port, name, ...)` is
  the testable seam — an `/etc/hosts` match short-circuits, a miss falls through
  to `DnsResolveA`; `DnsResolveHost(name, ...)` reads `/etc/hosts` +
  `/etc/resolv.conf` via PAL and resolves through the first configured
  nameserver on port 53, returning `DNS_ERR_NOCONFIG` when nothing matches and
  no nameserver is set (never public DNS). `test/lib_dns_facade.pas` proves the
  seam (hosts hit without a query; miss served by the forked mock, 8/8) and the
  live path was smoke-checked: `DnsResolveHost('localhost')` -> 127.0.0.1 from
  the real `/etc/hosts`. The libc-free `dns_wire` resolver is now a complete
  working vertical (codec -> config -> blocking transport -> facade); the
  REMAINING items above are incremental on top.
- 2026-07-10 — **AAAA + CNAME chase + search/ndots landed** (Track B):
  - `dns_wire_core`: `DnsBuildQuery(qtype)` generalization (A wrapper kept),
    `DnsParseResponseAAAA` (TDnsIpv6/TDnsIpv6Array), `DnsExtractCname` with a
    compression-following, hop-bounded name decoder.
  - `dns_config`: `DnsParseResolvConfEx` (search/domain last-wins, `options
    ndots:N` capped at 15) + `DnsQueryCandidate` (glibc candidate order:
    trailing-dot absolute; >= ndots as-is first; else search first, bare last).
  - `dns_wire_blocking`: transport factored into `DnsQueryOnce` (UDP + TC->TCP
    fallback shared by all query types); `DnsResolveAEx`/`DnsResolveAListEx`
    (CNAME target out) and `DnsResolveAAAA`.
  - `dns.pas`: `DnsResolveChase` (cross-query CNAME chain, bound 4);
    `DnsResolveHost` now walks the search-candidate list and chases aliases.
  - Tests: lib_dns_wire (AAAA encode/parse, compressed CNAME extract),
    lib_dns_config (Ex parse + candidate order), new `test/lib_dns_chase.pas`
    (forked mock serves CNAME then A; resolver follows with a second query).
    All in `make lib-test`, green against stable v194.
  REMAINING: async sibling over asyncnet, `dns_libc`/`dns_resolved`/`dns_esp`
  backends + profile selection, AAAA facade entrypoint (`DnsResolveHost6`),
  negative-response caching.
