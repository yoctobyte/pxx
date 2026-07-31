---
summary: "Policy: IPV6_V6ONLY on a :: listener, and which address wins when a host has both A and AAAA"
type: idea
track: U
prio: 40
---

# decide: dual-stack listeners, and A-vs-AAAA ordering

- **Type:** decision (Track U — human policy call, escalate-don't-guess)
- **Status:** backlog
- **Opened:** 2026-07-31, closing out the plumbing half of
  [[feature-ipv6-complete-surface]]. That ticket names both of these as design
  choices rather than plumbing, and says so in its own text — item 4 explicitly
  asks for a `decide-` if the answer is not obvious when reached. It was not.

Two questions, filed together because a caller meets them in the same breath:
"I want to serve everyone" and "I want to reach that host".

## 1. `IPV6_V6ONLY` on a `::` listener

`NetTcpListen(NetAny6(port))` currently sets nothing, so whether a v4 client can
reach that listener is **whatever the host default is** — on Linux,
`/proc/sys/net/ipv6/bindv6only`, which distributions set differently and an
administrator can change under a running program.

| option | what a `::` listener does | cost |
| --- | --- | --- |
| **V6ONLY = 0** (dual-stack) | one socket serves v4 and v6; v4 peers arrive as `::ffff:a.b.c.d` | peer addresses are v4-mapped, so anything comparing or logging an address has to understand that form. Not available on every OS. |
| **V6ONLY = 1** (strict) | `::` is v6 only; a server that wants both opens two sockets | predictable and portable, and the peer address is always what it looks like. Two sockets is more code for the caller. |
| **leave inherited** (today) | depends on the host | the same program behaves differently on two machines, silently. Not defensible as a *choice*, only as an omission. |

Whatever is chosen, "leave it inherited" should stop being the answer.
Recommendation: **V6ONLY = 1, set explicitly**, and let a server that wants both
families bind two listeners. It is the predictable one, the peer address never
needs decoding, and it does not depend on a sysctl. Note this is the opposite of
what Go's net package defaults to, so it is a real fork and not a formality.

## 2. Which address to use when a host has both A and AAAA

The resolver does not do AAAA lookups yet, so this is unblocked ground rather
than a change in behaviour.

| option | rule | cost |
| --- | --- | --- |
| **AAAA first, fall back on failure** | try v6, then v4 | on a host with broken v6 routing every connection eats a full timeout first — the classic complaint that happy eyeballs exists to solve |
| **A first** | try v4, then v6 | never slow, never advances v6 adoption |
| **Happy Eyeballs (RFC 8305)** | start the v6 connect, start the v4 one ~250 ms later, take whichever completes | correct, and what browsers do; needs two concurrent connects, which the async path can express and the blocking path cannot |
| **caller decides** | an explicit preference on the address/resolve call | honest, and pushes the question onto every caller |

Recommendation: **AAAA-first with a fallback for the blocking path, and Happy
Eyeballs on the async path**, since `asyncnet` already has the reactor that
makes two in-flight connects natural. But the timeout risk in option 1 is real
enough that this should be a deliberate call.

## What it unblocks

Items 4 and 5 of [[feature-ipv6-complete-surface]] — its other four items are
done. Nothing else is waiting.
