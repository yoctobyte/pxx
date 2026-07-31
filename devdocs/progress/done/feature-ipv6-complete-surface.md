---
summary: "Finish IPv6: PalAcceptIpv6, UDP v6, asyncnet, AAAA lookups, dual-stack listeners"
type: feature
track: B
prio: 40
---

# Finish the IPv6 surface (UDP, accept peer, asyncnet, AAAA, dual-stack)

- **Type:** feature — **Track B** (`lib/rtl`).
- **Status:** working
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

## 2026-07-31 — four of the six items DONE; the other two are a Track U call

### Landed

1. **`PalAcceptIpv6`.** Posix backend fills a real `sockaddr_in6` and a
   `ParseSockAddrIpv6` reads back the address, the wire-order port AND the scope
   id — a link-local peer is unanswerable without the last one. `NetTcpAccept6`
   now returns a real peer instead of a family with an empty address. The ESP
   backend refuses with `PAL_ERR_UNSUPPORTED` and zeroes the out-parameters,
   which is the same honesty rule bind/connect already follow there.
2. **UDP over v6.** `PalSendToIpv6` / `PalRecvFromIpv6` in the PAL, and
   `NetUdpBind` / `NetUdpSendTo` / `NetUdpRecvFrom` branch on family exactly as
   the TCP path does. `NetUdpBind` was creating an `AF_INET` socket regardless of
   the address it was handed; it now uses `addr.Family`. On receive it is the
   CALLER's `src` that says which family to read back, and that is documented at
   the declaration.
3. **`asyncnet`.** `TcpListen6` / `TcpConnect6` / `TcpConnectAddr6`. Only the
   four socket-CREATING calls needed pairs — `TcpAccept`, `TcpRecv`, `TcpSend`
   and `TcpClose` take an fd whose family was decided when it was made, so the
   reactor half needed no change at all. The unit header now says which is which.

### Gated

- `test/lib_net6.pas` extended: the accepted peer must actually BE `::1` with a
  nonzero ephemeral port (not merely carry `AF_INET6`), a v6 UDP round trip
  checks payload *and* sender address *and* sender port, and the v4 UDP path is
  asserted unchanged beside it.
- `test/lib_asyncnet6.pas` (new): a server and a client coroutine on one thread,
  both parked on the epoll reactor, over `::1`.
- Both SKIP cleanly on a host without `AF_INET6`, like `lib_ipv6` already did.

### Not done, and deliberately not guessed

Items **4 (A vs AAAA ordering)** and **5 (`IPV6_V6ONLY`)** are the two this
ticket itself calls design choices rather than plumbing — item 4 says in so many
words to file a Track U `decide-` if the answer is not obvious when reached. It
was not: V6ONLY=1 is predictable and V6ONLY=0 is what most of the world defaults
to, and AAAA-first costs a full timeout on a host with broken v6 routing. Filed
as [[decide-ipv6-dualstack-and-aaaa-ordering]] with the trade-offs and a
recommendation.

Item **6 (scopeId)** is now plumbed all the way through accept and UDP, but
still only exercised as a zero — proving it needs a real link-local peer on a
real interface index, which this box cannot arrange. The value is carried and
returned correctly; that it is carried is all this ticket can honestly claim.

- 2026-07-31 — resolved, commit da971d179.
