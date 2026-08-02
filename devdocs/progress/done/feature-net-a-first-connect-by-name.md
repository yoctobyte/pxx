---
track: B
prio: 35
type: feature
status: done
owner: claude-B
---

# Connect-by-name with A-first, AAAA-fallback ordering

- **Type:** feature (Track B networking)
- **Filed:** 2026-08-02, re-filing decided policy into the owning lane.
  [[decide-ipv6-dualstack-and-aaaa-ordering]] was **resolved 2026-08-01**, but
  its owning ticket [[feature-ipv6-complete-surface]] was already in `done/`,
  so the decided work had no home and was sitting in nobody's queue. Per
  CLAUDE.md, a U item that turns out to be plain work once decided is re-filed
  into the owning lane — this is that.

The decision's other half (the `IPV6_V6ONLY` escape hatch on `NetTcpListen`)
landed with the same sweep; this is what remains.

## The decision, verbatim in effect

> **A-first, AAAA fallback on failure. No Happy Eyeballs.** Not just simpler —
> the timeout-on-first-try risk is symmetric regardless of which family goes
> first, and IPv4 connectivity remains the more reliably-working leg in
> practice (CGNAT still connects; broken/absent v6 routing is still the more
> common failure mode). Leading with v4 is the safer default on reliability
> grounds alone, independent of any v6-adoption argument, which this project
> does not care about pushing. Happy Eyeballs' concurrency complexity buys
> nothing without that goal.

So: resolve A, try each address; on failure resolve AAAA and try those. No
concurrent connects, no 250 ms racing.

## The one thing that is NOT decided, and needs settling first

**Which unit owns it.** `net.pas` deliberately `uses platform` and nothing
else — no resolver dependency at all — and that separation is explicit in
[[feature-networking]]'s design notes (DNS was split out precisely so the
transport did not depend on it). A `NetTcpConnectHost(name, port)` inside
`net.pas` would couple transport to resolver and break that.

Options:

1. **A new thin unit** (e.g. `netconnect.pas`) that `uses net, dns` and owns
   the policy. Keeps both existing units dependency-clean; costs one more unit
   name. *Recommended* — the policy is genuinely a third thing, sitting above
   both.
2. **In `dns.pas`** as a `DnsConnect`-style helper. Wrong direction: the
   resolver would then depend on the transport.
3. **In `net.pas`** with a conditional dependency. Reintroduces exactly the
   coupling the umbrella's design avoided.

This is a routine structural call rather than a policy fork, so it does not
need another `decide-` — but it should be made deliberately and written down,
not drifted into.

## Also worth doing here

`asyncnet` has the reactor that would make Happy Eyeballs natural, and the
decision explicitly declined it. Worth a one-line note in `asyncnet` saying so,
so the next person does not implement it thinking it was merely missing.

## Gate

`localhost` resolves and connects with no network (it has both A and AAAA in
`/etc/hosts`, so it exercises the ordering for real): the v4 address is tried
first, and a host with only AAAA still connects via the fallback. A name with
neither returns a clean error rather than hanging. Assert the ORDER
observably — e.g. the connected socket's family — not just that a connection
happened, since "it connected" passes under either ordering.

## Landed 2026-08-02 (commit ec221f7a0)

`lib/rtl/netconnect.pas` — `NetConnectHost` / `NetConnectHostTimeout` /
`NetConnectHostEx`, implementing the decided A-first, AAAA-fallback ordering.

### The structural question, answered as recommended

**Option 1: its own unit.** `net.pas` still `uses platform` and nothing else,
`dns.pas` still knows nothing about sockets, and `netconnect` is the only place
in the tree that depends on both. The policy genuinely is a third thing sitting
above the two, and keeping it there preserves the separation
[[feature-networking]]'s design was explicit about.

`asyncnet` carries no Happy Eyeballs and now says so in this unit's header: the
decision declined it deliberately, and asyncnet's reactor is exactly what would
make it tempting, so the note is there to stop someone "fixing" an omission that
is a decision.

### Error shape

`NETCONNECT_ERR_NORESOLVE` only when NEITHER family resolved. If addresses were
found and every one refused, the LAST connect error is returned instead, so the
caller sees the real errno (ECONNREFUSED, ETIMEDOUT) rather than a generic
failure — the distinction between "no such host" and "host is down" is one
callers act on differently.

### A bug found by writing the test, not by the test passing

The first run had `fallback_family_v6` failing while the connection succeeded.
Cause: the `::` listener inherited `bindv6only=0`, so it was **dual-stack** and
accepted the IPv4 attempt — A-first succeeded and the fallback never ran. The
test would have passed for the wrong reason had it only asserted "connected".
Fixed by pinning the listener `NET_V6ONLY_ON` (the knob added earlier in this
same sweep), which is what makes "v4 must fail here" actually true.

That then exposed a **real defect in `net.pas`**:

> `NetTcpConnectTimeout` was IPv4-only. It hard-coded `PAL_NET_AF_INET` and
> `PalConnectIpv4`, ignoring `addr.Family` — missed when IPv6 landed in that
> unit, while the plain `NetTcpConnect` was updated correctly.

So a v6 address silently produced a v4 socket connecting to `addr.Host`, which
is 0 for a v6 address: a connect to `0.0.0.0` rather than an error. It hid
because every existing v6 test used `NetTcpConnect`. Fixed to branch on family
like its sibling, with a direct regression in `test/lib_net6.pas` (verified to
fail with `-111` when reverted) plus the v4 path through the same call asserted
unchanged.

### Verified

IP literal connects with no resolution and reports family v4; `localhost`
prefers v4 when both families are reachable; with a strict-v6 listener the v4
attempt fails and the AAAA fallback connects and reports family v6; an
unresolvable name returns `NETCONNECT_ERR_NORESOLVE`; a resolvable name with
nothing listening returns the real errno instead.

Test: `test/lib_netconnect.pas`, in `lib-test`, `localhost` only so it needs no
network.

## Log
- 2026-08-02 — resolved, commit PENDING.
