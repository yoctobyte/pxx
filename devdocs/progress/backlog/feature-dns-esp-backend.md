---
track: B
prio: 35
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

## Correction 2026-08-02 — this is an ENABLER, not an optimisation

Filed claiming "`dns_wire` already works on ESP in principle — it is pure Pascal
over PAL — so this is an optimisation and an integration nicety, not an enabler.
Nothing is blocked on it." **That looks wrong**, and the open question below is
how it surfaced — it was checked rather than left hanging:

- `lib/rtl/dns_config.pas` has **zero** ESP handling (measured: no
  `PXX_PAL_ESP_IDF_TARGET` / `ESP_IDF` reference in it or in
  `dns_wire_blocking.pas`).
- `dns_wire` gets its nameservers from `/etc/resolv.conf` through the PAL.
  ESP-IDF does provide a VFS, so `PalOpen` itself would work — but nothing in
  this tree ever creates such a file on ESP, and an ESP device's DHCP-supplied
  nameservers live inside lwIP, not on a filesystem.

So on ESP `dns_wire` should reach `DNS_ERR_NOCONFIG` for every name, meaning DNS
does not work there at all and this ticket is the enabler. Re-ranked 20 → 35.

**Not run-verified.** This is read off the code and the ESP backend, not measured
on hardware — there is no ESP runner here. Confirm it on a device before trusting
it, because the point of this note is that the original claim was equally
plausible and equally unchecked.

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

Sequencing note, now answered: `dns_config` has no ESP story, so **this ticket
is really two** and should be split when picked up:

1. **Where do nameservers come from on ESP?** Either a `dns_config` source that
   reads lwIP's DHCP-supplied servers, or an app-supplied resolv.conf-shaped
   text. This half also fixes `dns_wire` on ESP and is worth doing even if the
   lwIP resolver backend never lands.
2. **The `dns_esp` backend proper** — hand the name to lwIP's own resolver so it
   uses its cache and its DHCP servers.

Doing (2) without (1) leaves `dns_wire` broken on ESP as the *fallback* path,
which is what every build without `-dPXX_DNS_ESP` gets.

## Not startable on the current fleet — checked 2026-08-02

Picked up as queue-top after the re-rank above and put back down, so the next
agent does not repeat the check:

- `xtensa` and `riscv32` **compile** here, and `tools/run_target.sh riscv32`
  runs a binary under `qemu-riscv32`.
- But that is Linux userspace, not ESP-IDF. lwIP's `dns_gethostbyname` does not
  exist in it, so the backend's entire behaviour — the thing worth verifying —
  cannot be exercised. Writing extern declarations against an API that nothing
  available can link or answer is how a plausible-wrong binding gets committed.

So this wants an ESP device or a QEMU-ESP image in the loop before it starts.
That is the same gap as item (b) of [[feature-real-dynlib-loader]] (other-target
run verification), and it is worth solving once for both rather than per-ticket.

## Gate

Runs on real ESP hardware (or QEMU-ESP where that exists) against a name the
lwIP resolver can answer; the host-side build must be unaffected, which the
existing `lib-test` DNS entries already assert by building the default and the
resolved variants. Cannot be gated on the normal x86-64 lib gate — state that
plainly in the ticket rather than pretending the usual gate covers it.
