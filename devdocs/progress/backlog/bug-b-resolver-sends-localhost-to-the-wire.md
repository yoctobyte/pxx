---
track: B
prio: 45
type: bug
blocked-by: []
summary: "lib/rtl/dns.pas has no `localhost` special-case, so when /etc/hosts lacks a matching line the name is sent to the configured nameserver and whatever answer comes back is used. RFC 6761 6.3 says resolvers SHOULD always return loopback for localhost names; glibc complies, we do not. Masked for IPv4 by the conventional hosts line, unmasked for IPv6 on Debian/Ubuntu."
status: backlog
owner: unassigned
---

# The resolver sends `localhost` to the wire

- **Type:** bug — Track B (`lib/rtl/dns.pas`).
- Found 2026-08-28 while correcting a false hermeticity claim in
  `test/lib_dns_libc.pas`; see
  [[bug-b-lib-dns-libc-failed-once-in-the-gate-and-claims-a-hermeticity-it-lacks]].

## Measured

`grep -rni localhost lib/rtl/dns.pas lib/rtl/dns_config.pas
lib/rtl/dns_wire_core.pas` returns **nothing**. There is no special-case; the
name takes the ordinary "files dns" path, and when files miss it goes to the
nameservers with the usual search-list expansion.

On this box (`/etc/hosts` has `127.0.0.1 localhost`, and spells the v6 loopback
`ip6-localhost`, which is the Debian/Ubuntu convention — there is no
`::1 localhost` line):

| call | contacts to port 53 |
| --- | --- |
| `DnsResolveHost('localhost')` | 0 — files hit |
| `DnsResolveHost6('localhost')` | **6** — files miss, then `localhost.home`, `localhost.<search>`, `localhost.` go to 127.0.0.53 |
| glibc `getaddrinfo("localhost")` | 0, answers `::ffff:127.0.0.1` |

So the v4 case is not correct, merely **masked** by a hosts line that almost
every box happens to have. Remove that line, or ask for AAAA, and the name goes
to the network.

## Why this is a bug rather than a preference

RFC 6761 section 6.3, verbatim:

> "Name resolution APIs and libraries SHOULD recognize localhost names as
> special and SHOULD always return the IP loopback address for address queries"

We do neither. The consequence is not cosmetic: a name that must always mean
loopback is instead **answered by the network**, so a hostile or merely
misconfigured DNS server — or a wildcard search domain, which is how this was
actually observed — can return a non-loopback address for `localhost`. A program
that connects to `localhost` expecting a local service would then connect
somewhere else. That is a behaviour a correct program can observe, which is the
silent-wrong-behaviour escape rather than a parity nit.

**Do not reason from `.invalid` here.** RFC 6761 section 6.4 gives `.invalid` a
DIFFERENT prescription — "SHOULD always return immediate negative responses" —
so the observation that glibc happily queries `.invalid` says nothing whatever
about `localhost`. That inference was made during this investigation and was
wrong; it is recorded so it is not made again.

## Fix sketch

A special-case ahead of the files lookup in the `DnsResolveHost` /
`DnsResolveHost6` path: `localhost` and any name ending in `.localhost`
(6.3 covers the subdomains too) answer `127.0.0.1` / `::1` immediately, without
consulting files or the wire. It must precede the search-list expansion, since
the expansion is what generated the queries above.

Worth deciding while implementing rather than guessing: whether an explicit
`/etc/hosts` entry for `localhost` should be allowed to override the built-in
answer. The RFC says the RDATA "cannot be modified by local configuration",
which argues for the special-case winning outright, but every real
implementation still reads the hosts file first and no in-tree caller depends on
either order.

## Gate

Track B's: build with `$(PXX_STABLE)`, `make lib-test`. The test that bites is a
strace-style assertion that resolving `localhost` and `localhost` AAAA produce
**zero** packets to port 53 — the current v6 behaviour passes any functional
test on a box whose resolver answers, which is exactly how this survived.
`test/lib_dns_libc.pas` now asserts the v6 facade against the `::1` literal
instead, so it no longer depends on the network, but it does not yet assert the
absence of traffic.
