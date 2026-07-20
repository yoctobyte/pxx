---
summary: "Finish IPv6: PalAcceptIpv6, UDP v6, asyncnet, AAAA lookups, dual-stack listeners"
type: feature
track: B
prio: 40
---

# Finish the IPv6 surface (UDP, accept peer, asyncnet, AAAA, dual-stack)

- **Type:** feature — **Track B** (`lib/rtl`).
- **Status:** backlog — filed 2026-07-20.
- **Parent:** [[feature-networking]]. Split out so the remaining IPv6 work is
  visible and rankable on its own instead of living inside a strategy umbrella.

## Already landed (2026-07-20)

- PAL: `TPalIn6Addr`, `PalBindIpv6`, `PalConnectIpv6`, `PalIn6Loopback`,
  `PalIn6Any`; real `sockaddr_in6` in the posix backend; ESP backend refuses
  honestly with `PAL_ERR_UNSUPPORTED`.
- `net.pas`: `TNetAddress` carries `Family`/`V6`/`ScopeId`; `NetAddress6`,
  `NetLoopback6`, `NetAny6`, `NetIsV6`, `NetTcpAccept6`; listen/connect branch on
  family.
- Gated: `test/lib_ipv6.pas` (PAL) and `test/lib_net6.pas` (net.pas, plus proof
  the v4 path is unchanged).

So TCP client and server speak IPv6 today.

## Remaining

1. **`PalAcceptIpv6`.** `NetTcpAccept6` currently sets the peer's `Family` but
   not its address, because the PAL's accept fills an IPv4 `sockaddr`. Reporting
   a zeroed v6 peer as if it were real would be worse than reporting nothing,
   which is why it is left empty — but it needs finishing before anything logs
   or authorises on a peer address.
2. **UDP over v6** — `NetUdpBind` / `NetUdpSendTo` / `NetUdpRecvFrom` are still
   IPv4-only, and the PAL needs `PalSendToIpv6` / `PalRecvFromIpv6`.
3. **`asyncnet`** — the coroutine/epoll reactor is IPv4-only; the same
   family branch as `net.pas` applies.
4. **AAAA lookups** in the resolver, and a happy-eyeballs-ish ordering decision
   when a host has both A and AAAA. That ordering is a real design choice, not
   just plumbing — file it as a Track U `decide-` if it is not obvious when
   reached.
5. **Dual-stack listeners** — `IPV6_V6ONLY` is untouched, so a `::` listener's
   behaviour for v4-mapped clients is currently whatever the host default is.
   That should be an explicit, documented choice rather than inherited.
6. **`scopeId`** is plumbed through but untested — only a link-local
   (`fe80::/10`) connection exercises it, which needs a real interface index.

## Acceptance

- A v6 peer address comes back from accept.
- UDP round trip over `::1`, gated.
- `asyncnet` accepts and connects over v6.
- A host with both A and AAAA resolves and connects by a documented rule.
- `IPV6_V6ONLY` set deliberately, with the choice written down.

## Log
- 2026-07-20 — Filed from the Track B sweep, splitting the concrete remainder
  out of [[feature-networking]].
