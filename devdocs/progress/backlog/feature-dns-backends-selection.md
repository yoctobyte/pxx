---
prio: 40
---

# DNS backends beyond dns_wire: dns_libc / dns_resolved / dns_esp + selection

- **Type:** feature (Track B networking / resolver policy)
- **Status:** backlog
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

## Acceptance

- At least one non-wire backend usable behind an explicit define/profile, with
  `dns.pas`'s API unchanged for callers.
- Selection documented; `dns_wire` remains the default everywhere.
- Public-DNS fallback still impossible without explicit opt-in.
