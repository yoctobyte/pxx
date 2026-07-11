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

## Remaining work

The `dns_wire` backend (pure Pascal over PAL) is DONE and is the de-facto
default: codec, /etc/hosts (v4+v6) + resolv.conf + /etc/services config,
blocking + async transports, UDP with TC->TCP fallback on both, glibc
search/ndots candidates, CNAME chasing, and a process-wide TTL cache
(A/AAAA/CNAME/negative). What's left from the design:

1. **`dns_libc`** — `getaddrinfo()` for maximum system compatibility (NSS,
   mDNS, nsswitch policy). **Blocked on a design decision:** PXX-emitted
   executables are libc-free static ELF; linking libc statically is not the
   model. Realistic shapes: (a) `dlopen("libc.so.6")` + `getaddrinfo` via the
   existing dynlib machinery (the design notes call this `dns_libc_dyn` and
   rank it low), or (b) a C-frontend-compiled shim linked in via crtl. Decide
   with the user before building.
2. **`dns_resolved`** — systemd-resolved over D-Bus (honors split DNS / VPN
   routing domains). Needs AF_UNIX in PAL + a minimal D-Bus client. Sizable;
   possibly its own ticket when picked up.
3. **`dns_esp`** — ESP-IDF/lwIP resolver API after netif bring-up; ESP-only.
4. **Selection mechanism** — per the design: crude first slice = compile
   defines (`PXX_DNS_WIRE` / `PXX_DNS_LIBC` / ...), final shape = the scoped
   profile/config system. `auto` = compile-time choice by target; runtime
   fallback (`auto_fallback`) opt-in only. Public DNS fallback stays opt-in
   and off by default (hard policy).

## Acceptance

- At least one non-wire backend usable behind an explicit define/profile, with
  `dns.pas`'s API unchanged for callers.
- Selection documented; `dns_wire` remains the default everywhere.
- Public-DNS fallback still impossible without explicit opt-in.
