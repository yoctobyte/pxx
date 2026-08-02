---
track: B
prio: 55
type: bug
---

# `dns_wire` answers NXDOMAIN for an IPv4 literal, so the facade's answer depends on the backend

- **Type:** bug (RTL resolver, wrong answer + backend divergence) — **Track B**
  (`lib/rtl/dns.pas`)
- **Found and fixed:** 2026-08-02, while starting
  [[feature-net-a-first-connect-by-name]] — a connect-by-name entry point has to
  accept a literal, so the first thing checked was whether the resolver does.

## Measured

`DnsResolveHost('127.0.0.1', ...)` through the facade, same program, three
builds, against `getent` as the oracle:

| backend | result |
| --- | --- |
| **dns_wire (the DEFAULT)** | **rcode 3 (NXDOMAIN), no address** |
| dns_resolved | rcode 0, `127.0.0.1` |
| dns_libc | rcode 0, `127.0.0.1` |
| `getent ahostsv4 127.0.0.1` | `127.0.0.1` |

Two separate defects in one:

1. **Wrong answer.** An IP literal resolves to itself; every other resolver in
   reach agrees. `dns_wire` sent it to a nameserver as a hostname and reported
   the NXDOMAIN that came back.
2. **Backend divergence.** The selection design's whole promise is that
   `dns.pas` "stays the same API whichever backend is selected", and this broke
   it observably: the same program answers differently depending on a `-d`
   flag. That is worse than the wrong answer alone, because it makes the
   backends untestable against each other — the comparison I had been using to
   validate `dns_resolved` and `dns_libc` would have quietly accepted a
   divergence in either direction.

It was also internally inconsistent: `DnsResolveHost6` has short-circuited an
IPv6 literal since it was written, and its interface comment says so. Only the
v4 path lacked it.

## Fix

`DnsWireResolveHost` short-circuits an IPv4 literal before touching
`/etc/hosts` or any nameserver, mirroring the v6 path exactly. `DnsParseIpv4`
already existed in `dns_config` — the v4 path simply never called it. The
interface comment now documents the short-circuit as the v6 one does.

## Verified

All three backends now return `127.0.0.1` with rcode 0. The assertions live in
`test/lib_dns_resolved.pas` rather than a backend-specific test, deliberately:
this is a CROSS-backend contract, and `lib-test` builds that program both with
and without the define, so the two paths are checked against the same
expectations. Confirmed to fail (2 assertions) when the short-circuit is
disabled.

## Note for whoever adds a backend next

The comparison used to validate a new backend must include an IP literal.
Everything else this facade does — hosts file, search domains, CNAME chasing —
was consistent across backends; this was the one case where the default was the
odd one out, and it was found only by asking a question the tests never asked.
