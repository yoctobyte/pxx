---
track: B
prio: 20
type: feature
---

# `dns_esp` — the lwIP resolver on ESP targets

- **Type:** feature (Track B networking / resolver backends), ESP-only
- **Split out of** [[feature-dns-backends-selection]] on 2026-08-02 (item 3),
  when that ticket's acceptance was met by `dns_resolved` landing.

## What it is

ESP-IDF/lwIP exposes its own resolver (`dns_gethostbyname` / lwIP's
`netconn_gethostbyname`) once the netif is up. On ESP, that resolver already
holds the DHCP-supplied nameservers and the lwIP DNS cache, so going through it
is both cheaper and more correct than re-deriving configuration.

## Why it is low priority

`dns_wire` already works on ESP in principle — it is pure Pascal over PAL — so
this is an optimisation and an integration nicety, not an enabler. Nothing is
blocked on it. Ranked below [[feature-dns-libc-backend]] accordingly.

The one thing that IS ESP-specific and already handled: `PalConnectUnix` reports
`PAL_NET_ENOTSUP` on the ESP backend, because lwIP has no filesystem sockets, so
`dns_resolved` can never be selected there. That is a clean refusal rather than
an obscure connect failure — see `lib/rtl/platform/esp/platform_backend.pas`.

## Shape

A `dns_esp` unit behind `-dPXX_DNS_ESP`, following exactly the pattern
`dns_resolved` established in `dns.pas`: the wire path stays compiled and is the
fallback, only `DnsResolveHost` / `DnsResolveHost6` dispatch, and selecting two
backends at once is a compile-time error (the guard already exists — extend it
to the new define).

Sequencing note: unlike the other backends this one cannot fall back to
`dns_wire` for *configuration* reasons — on ESP there is no `/etc/resolv.conf`
at all, so `dns_wire`'s config layer needs a story on that target regardless of
this ticket. Worth checking before starting whether `dns_config` already has
one, since if it does not, this ticket is really two.

## Gate

Runs on real ESP hardware (or QEMU-ESP where that exists) against a name the
lwIP resolver can answer; the host-side build must be unaffected, which the
existing `lib-test` DNS entries already assert by building the default and the
resolved variants. Cannot be gated on the normal x86-64 lib gate — state that
plainly in the ticket rather than pretending the usual gate covers it.
