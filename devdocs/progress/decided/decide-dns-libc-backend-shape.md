---
summary: "Track U: how should a libc-backed DNS resolver be reached from libc-free static ELF?"
type: decide
prio: 40
track: U
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — (c) first, (a) deferred not rejected

**User's call.** Build `dns_resolved` first (no glibc/ABI dependency, fits
the static-ELF model). `dns_libc` (option a, dlopen+`getaddrinfo`) is
**deferred, not rejected** — real deployments (VPN split-DNS via nsswitch,
custom NSS modules) need it and `dns_resolved` doesn't cover them, since
its own dependency (systemd + `resolved` running + D-Bus reachable) is not
universal either — musl distros, minimal containers, and plenty of systemd
hosts without `resolved` enabled all miss it. The two backends' gaps are
roughly disjoint, not one strictly subsuming the other. `dns_wire` (already
done, zero dependencies) stays the default throughout, always.
`feature-dns-backends-selection` updated: `dns_libc` re-ranked as real
follow-up work, not left to rot like the GPC wish did.

### Selection mechanism (designed here, since it was undesigned)

Matches the existing `-d<DEFINE>` conditional-compile convention already
used for build-time variants (`-dPXX_MANAGED_STRING`, `-dPXX_HEAP_DEBUG`,
`-dPXX_OBJTRACE`):

- No define → `dns_wire` (default, unconditionally available).
- `-dPXX_DNS_RESOLVED` → `dns_resolved` backend.
- `-dPXX_DNS_LIBC` → `dns_libc` backend (once built).
- Both defined at once → **compile-time error**, not silent precedence —
  ambiguous backend selection is exactly the kind of thing that should be
  loud, matching this project's stance elsewhere (platonic code, no silent
  workarounds).

`dns.pas` (the facade unit) stays the stable public entrypoint; each
backend is its own implementation unit (`dns_wire_core`/`dns_resolved_impl`/
`dns_libc_impl`, mirroring how `dns_wire_core`/`dns_wire_blocking`/
`dns_async`/`dns_cache` are already split), and `dns.pas`'s `uses` clause
picks the right one under `{$ifdef}`. A later "scoped profile/config
system" (mentioned in the original ticket as the eventual final shape) is
still future work, not designed here — this is the crude-but-real
first slice.

# decide: the shape of a libc-backed DNS backend

- **Type:** decision — **Track U**. No files, no gate; this unblocks work rather
  than being work.
- **Status:** open — filed 2026-07-20.
- **Blocks:** [[feature-dns-backends-selection]] item 1 (`dns_libc`).
- **Raised by:** Track B, while sweeping the Track B queue — the ticket says
  "Decide with the user before building", and nothing had been filed to actually
  ask, so it read as available work when it is not.

## The fork

`dns_libc` would let the resolver honour the host's real name-resolution policy —
`/etc/nsswitch.conf`, mDNS, split-DNS from a VPN — instead of only what
`dns_wire` implements. Getting there means calling `getaddrinfo`, which lives in
libc, and **PXX emits libc-free static ELF**. Static-linking libc is not the
model, so something has to give.

## Options

**(a) `dlopen("libc.so.6")` + `getaddrinfo` through the existing dynlib machinery.**
The loader already exists and works on x86-64 ([[feature-real-dynlib-loader]]).
Cheapest path. Costs: a runtime dependency on a glibc that may not be present
(musl hosts, containers built FROM scratch), and `getaddrinfo`'s struct layout
is glibc-version-sensitive in a way a hand-written binding will eventually get
wrong. The design notes already rank this low.

**(b) A C-frontend-compiled shim linked in via crtl.** We compile the shim
ourselves, so no runtime libc dependency and no ABI guessing — but it only
resolves what our own crtl implements, which brings us most of the way back to
`dns_wire` and does *not* give nsswitch/mDNS/VPN policy. That is the entire
reason someone would want `dns_libc`, so this option arguably answers a
different question than the one asked.

**(c) Don't build `dns_libc` at all.** Make `dns_wire` (already done and
vertical) plus `dns_resolved` (item 2 — systemd-resolved over D-Bus, which is a
documented wire protocol and needs no libc) the supported set. `dns_resolved`
delivers the split-DNS/VPN behaviour that motivates (a) without the ABI
exposure, on every systemd host — which is most Linux desktops and servers.

## Recommendation

**(c), with `dns_resolved` promoted.** It reaches the actual goal — host
resolution policy — without a glibc runtime dependency or a version-sensitive
struct binding, and it fits the libc-free story rather than working around it.
If a non-systemd host with exotic nsswitch rules ever turns up as a real
requirement, revisit (a) then, with a concrete case to test against.

Worth noting the counter-argument: (a) is much less work and would land sooner,
and "the host's resolver, whatever it is" is a genuinely stronger promise than
"systemd's resolver". If the priority is breadth of host compatibility rather
than purity of the static-ELF model, (a) wins.

## Once decided

Re-file the chosen shape as ordinary Track B work under
[[feature-dns-backends-selection]] and drop the `blocked-by` edge from that
ticket. If (c), close item 1 as rejected and re-rank item 2.

## Log
- 2026-07-20 — Filed from Track B so the decision is visible in the queue rather
  than buried in a sub-item of an implementation ticket.
