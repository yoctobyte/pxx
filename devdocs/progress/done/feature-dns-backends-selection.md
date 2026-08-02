---
prio: 40
owner: claude-B
---

# DNS backends beyond dns_wire: dns_libc / dns_resolved / dns_esp + selection

- **Type:** feature (Track B networking / resolver policy)
- **Status:** done
- **Opened:** 2026-07-11, split out of [[feature-dns-resolver-library]] when the
  pure-wire resolver vertical completed. All design text (backend pros/cons,
  selection policy, defaults) lives in that ticket — this one carries the
  remaining work.

## Sequencing, decided 2026-08-01 (see [[decide-dns-libc-backend-shape]])

Build `dns_resolved` (item 2) first. `dns_libc` (item 1) is real follow-up
work, not rejected — its gap (needs glibc) and `dns_resolved`'s gap (needs
systemd+`resolved`+D-Bus) are roughly disjoint, so neither alone reaches
every deployment (VPN split-DNS via nsswitch/custom NSS modules specifically
need `dns_libc`). `dns_wire` stays the zero-dependency default throughout.

## Selection mechanism, designed 2026-08-01

`-d<DEFINE>` on the pxx command line, matching the existing convention
(`-dPXX_MANAGED_STRING`, `-dPXX_HEAP_DEBUG`): no define → `dns_wire`;
`-dPXX_DNS_RESOLVED` / `-dPXX_DNS_LIBC` → that backend. Both defined at
once is a **compile-time error**, not silent precedence. `dns.pas` stays
the stable facade; each backend is its own implementation unit picked via
`{$ifdef}` in `dns.pas`'s `uses` clause, mirroring the existing
`dns_wire_core`/`dns_wire_blocking`/`dns_async`/`dns_cache` split. A later
scoped profile/config system is still future work, not this slice.

## Remaining work

The `dns_wire` backend (pure Pascal over PAL) is DONE and is the de-facto
default: codec, /etc/hosts (v4+v6) + resolv.conf + /etc/services config,
blocking + async transports, UDP with TC->TCP fallback on both, glibc
search/ndots candidates, CNAME chasing, and a process-wide TTL cache
(A/AAAA/CNAME/negative). What's left from the design:

1. **`dns_libc`** — `getaddrinfo()` for maximum system compatibility (NSS,
   mDNS, nsswitch policy). Deferred behind `dns_resolved` (see sequencing
   above), not rejected. Shape: `dlopen("libc.so.6")` + `getaddrinfo` via
   the existing dynlib machinery ([[feature-real-dynlib-loader]]) — accept
   the glibc-runtime dependency and version-sensitive struct binding as the
   known cost of reaching real nsswitch/mDNS/VPN policy.
2. **`dns_resolved`** — systemd-resolved over D-Bus (honors split DNS / VPN
   routing domains). Needs AF_UNIX in PAL + a minimal D-Bus client. Sizable;
   possibly its own ticket when picked up. **Build this first.**
3. **`dns_esp`** — ESP-IDF/lwIP resolver API after netif bring-up; ESP-only.
4. **Selection mechanism** — see above, now designed.

## Landed 2026-08-02 — `dns_resolved` + the selection mechanism

Items 2 and 4. Items 1 (`dns_libc`) and 3 (`dns_esp`) remain; see below.

### Varlink, not D-Bus — the estimate changed

This ticket sized item 2 as "Needs AF_UNIX in PAL + a minimal D-Bus client.
Sizable; possibly its own ticket when picked up." That held for D-Bus. But
systemd-resolved also exposes a **Varlink** interface at
`/run/systemd/resolve/io.systemd.Resolve`, and Varlink is a NUL-terminated JSON
request and a NUL-terminated JSON reply on a stream socket:

- no binary marshalling, no type signatures, no auth handshake, no bus daemon
  in the path;
- the socket is `srw-rw-rw-`, so no privilege and no D-Bus policy file;
- the reply hands back `addresses: [{ifindex, family, address:[bytes]}]`, which
  is already the shape `TDnsIpv4Array` / `TDnsIpv6Array` want.

That is what turned a subsystem into one unit, and `lib/rtl/json.pas` already
existed to parse it. The cost is that Varlink needs systemd newer than v243 —
but a host that lacks the socket falls back to the wire path, which is exactly
what a missing D-Bus service would have done.

Verified against the live service by hand before any Pascal was written, then
the Pascal was diffed against that same oracle.

### What landed

- **PAL**: `PalConnectUnix` + `PAL_NET_AF_UNIX` (posix backend; the ESP backend
  reports `PAL_NET_ENOTSUP`, since lwIP has no filesystem sockets). A path too
  long for `sun_path` is **refused**, not truncated — a truncated path is still
  a valid path and would connect to a *different* socket than the caller named.
- **`lib/rtl/dns_resolved.pas`**: the Varlink client.
  `DnsResolvedResolveHost` / `...Host6` / `DnsResolvedAvailable`. A resolved
  lookup failure carries the DNS RCODE, so it maps straight onto what the wire
  path already returns (NXDOMAIN = 3).
- **Selection**: `-dPXX_DNS_RESOLVED`, per the designed convention. The wire
  path is always compiled and stays the default. Only the two POLICY
  entrypoints switch — `DnsResolveHost` / `DnsResolveHost6`; every other export
  is a wire building block and is untouched, so **the facade's API is identical
  either way**, which is the acceptance criterion.
- **Both defines at once is a compile-time error**, as specified, not silent
  precedence. `-dPXX_DNS_LIBC` alone is also a compile-time error naming itself
  as not yet implemented, rather than silently giving the caller `dns_wire`
  when they explicitly asked for something else. Both verified to fail the
  build with exit 1 and produce **no binary**.

### Fallback is part of the contract

`-dPXX_DNS_RESOLVED` does not make resolved a dependency. A missing socket or a
reply that is not the documented shape falls through to the wire path; only
those two conditions do. A real DNS answer — **including NXDOMAIN** — is
returned as-is, because falling back on a legitimate "no such name" would
re-query the public path and defeat the split-DNS policy that is the entire
reason for this backend.

Tested by building against a copy of the RTL with the socket path pointed at a
nonexistent file: resolution still succeeded, via wire.

### Verified

| check | result |
| --- | --- |
| resolved vs the Python Varlink oracle | identical addresses, v4 and v6 |
| resolved vs `dns_wire` through the facade | identical answers |
| NXDOMAIN | rcode 3, zero addresses |
| both defines / libc alone | compile error, exit 1, no binary |
| resolved absent | falls back to wire, still resolves |
| **cross-target** | i386, aarch64, arm32 byte-identical to x86-64 |

The cross-target run matters more than usual here: i386 reaches the kernel
through `socketcall` rather than a direct `connect` syscall, so it is a
genuinely different code path in the new PAL function. All four agree.

Test: `test/lib_dns_resolved.pas`, wired into `lib-test` **twice** — once
without the define (the default must not be disturbed by the backend existing)
and once with it. It uses only `localhost`, so it needs no network, and it
skips its resolved half where systemd-resolved is absent, that being a
supported configuration covered by the fallback assertion.

### Still open

Item 1 `dns_libc` and item 3 `dns_esp`. The acceptance below is met ("at least
one non-wire backend"), so the remaining two are follow-up work rather than
this ticket — recommend re-filing them as their own tickets, since `dns_esp` is
ESP-only and `dns_libc` needs the dynlib route.

## Acceptance

- At least one non-wire backend usable behind an explicit define/profile, with
  `dns.pas`'s API unchanged for callers.
- Selection documented; `dns_wire` remains the default everywhere.
- Public-DNS fallback still impossible without explicit opt-in.

## Log
- 2026-08-02 — resolved, commit PENDING.
