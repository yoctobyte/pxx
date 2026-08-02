---
track: B
prio: 35
type: feature
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
