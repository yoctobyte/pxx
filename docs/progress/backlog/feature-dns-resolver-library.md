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
