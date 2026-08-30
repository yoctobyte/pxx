---
slug: feature-dns-esp-wire-nameservers-from-lwip
track: B
prio: 15
type: feature
blocked-by: [decide-is-the-2026-07-12-esp-park-still-in-force]
summary: "Half 2 of the feature-dns-esp-backend split: where dns_wire gets its nameservers on ESP. Only matters for the explicit opt-in case -- someone who wants PXX's own resolver instead of lwIP's -- because the default route now goes through lwIP's getaddrinfo and never reads a nameserver list. dns_getserver is in liblwip.a for it; its ip_addr_t return wants a small C shim rather than hand-computed offsets."
status: backlog
---

# `dns_wire` on ESP has no nameservers — the opt-in half

- **Track B+S** (`lib/rtl`). Split out of [[feature-dns-esp-backend]] on
  2026-08-30, when that ticket's other half landed and it became separable.
- That ticket said in its own body that it "is really two and should be split
  when picked up". This is the second one.

## Why it is second, not first

The settled design put it there, and the reason survives the implementation:
the **default** ESP route now goes through lwIP's own resolver
(`-dPXX_DNS_LIBC` binds `lwip_getaddrinfo`), which holds the DHCP-supplied
nameservers and lwIP's cache internally. Nothing on that path ever reads a
nameserver list, so nothing on that path needs this.

This matters only for the **explicit opt-in**: someone who wants PXX's own wire
resolver on ESP instead of lwIP's — to bypass lwIP's cache, or to query a
chosen server.

## The gap, as measured

`lib/rtl/dns_config.pas` has **zero** ESP handling (no `PXX_ESP_IDF` /
`PXX_PAL_ESP_IDF_TARGET` reference in it or in `dns_wire_blocking.pas`).
`dns_wire` gets its nameservers from `/etc/resolv.conf` through the PAL. ESP-IDF
does provide a VFS so `PalOpen` itself would work, but nothing in this tree ever
creates such a file on ESP, and a device's DHCP-supplied nameservers live inside
lwIP rather than on a filesystem. So `dns_wire` should reach `DNS_ERR_NOCONFIG`
for every name there.

**Still not run-verified**, and worth stating twice because the parent ticket
had to correct itself on exactly this point: the reasoning above is read off the
code, not measured on a device. The parent's own note — *"the original claim was
equally plausible and equally unchecked"* — applies unchanged. Confirm it before
building against it. `examples/esp32/dns-c3` is now the cheapest place to check:
drop `-dPXX_DNS_LIBC` from its `build.sh` and see what the smoke reports.

## Shape

`dns_getserver` **is** in `liblwip.a` (verified alongside `lwip_getaddrinfo`),
so the servers are reachable. But its `ip_addr_t` return is a union whose tag
offset moves with `LWIP_IPV6_SCOPES`, so unlike `sockaddr_in` — where lwIP's
layout coincided with glibc's by luck and could be read by hand — this one
**wants a small C shim** calling `ip_addr_get_ip4_u32()` rather than
hand-computed offsets. That asymmetry is the whole design content here.

The alternative, and it may be the better first step: an app-supplied
resolv.conf-shaped text handed to `dns_config`, which needs no lwIP symbols at
all and also fixes the "no configuration" case for a device with a static IP.

## Gate

Same as the parent: cannot be gated on the normal x86-64 lib gate — say so
rather than pretending it is covered. `examples/esp32/dns-c3` under
`qemu-system-riscv32` with `-dPXX_DNS_LIBC` removed, plus `make lib-test` for
the host side of any `dns_config` change.

## Priority

Low (15), and lower than the parent was. Nothing is blocked on it, the default
route works without it, and ESP remains parked behind Pascal by the user's
standing call ("ESP parked (user 2026-07-12): Pascal has prio"). It is filed so
the design is not lost, not to schedule work.

## 2026-08-30 — blocked on the ESP-park decision, by the agent who filed it

Filed earlier today, ranked, and dispatchable within the hour — which is the
problem. The 2026-07-12 user ruling *"ESP parked: Pascal has prio"* exists as a
comment on a `prio:` field in one `done/` ticket plus prose in one backlog
ticket. It is enforced nowhere, so this row was about to be handed to the next
agent as ordinary p15 work while the question of whether ESP should be worked at
all is open as [[decide-is-the-2026-07-12-esp-park-still-in-force]].

`blocked-by:` that decision. **This does not presume its outcome** — it says
only "not dispatchable until the question is answered", which is true whichever
way it goes: if the park is lifted the edge clears and this ranks normally; if
it holds, it should never have ranked. The parent ticket already noted the park
in prose, and prose is exactly what the ranker cannot see — the same gap the
decision is about.

Narrow on purpose: this is the one ESP row I filed myself. The other 22 ranked
ESP/xtensa rows are not mine to gate, and gating them is part of what the
decision has to settle.
