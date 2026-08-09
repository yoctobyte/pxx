---
prio: 55
---

# Register the pxxc domain variants (.com, .nl, .eu) — REJECTED

- **Type:** chore (user action)
- **Track:** W (website)
- **Status:** **rejected 2026-08-09 by the user, same day it was filed.** The
  homework had already been done; the ticket restated a concern the user had
  already weighed and declined. pxxc.org is live and canonical, and that is the
  scope they want.
- **Owner:** —
- **Related:** [[docs-canonical-domain]], [[feature-web-tracker-and-host-portability]]

## What was actually checked (2026-08-09, DNS)

Filed on the assumption the variants were free. Verified before closing:

| domain | status | detail |
| --- | --- | --- |
| `pxxc.com` | **registered, not ours** | delegated at the `.com` registry to `ns1`/`ns2.cnolnic.com` (Baidu Cloud, `106.12.x` / `180.76.x`). Those nameservers do not answer — every recursive returns SERVFAIL. Taken and dead. |
| `pxxc.nl` | NXDOMAIN — free | not registered |
| `pxxc.eu` | NXDOMAIN — free | not registered |
| `pxxc.org` | ours, live | Cloudflare `aspen`/`patrick.ns.cloudflare.com` |

So the user's recollection was right about the priority item: `.com` was gone
before this was ever filed, which removes the "close it permanently for €30"
framing the ticket was built on. The two ccTLDs are in fact still available —
recorded here as a fact, not as a re-argument. The decision is made.

## Why it is not worth reopening on a whim

The parked `.com` is a fact about the world now, not a gap we can close. If
impersonation ever becomes a live concern, the defence that works is the one
[[feature-web-tracker-and-host-portability]] already owns: **our** signing key,
key continuity, and the fingerprint published in more than one place. That
verifies an artifact no matter which address it came from, which is the property
buying a domain never gives you. Reopen only if the user says so.

## Log
- 2026-08-09 — filed and rejected the same day. Filed when resolving
  [[docs-canonical-domain]], on the assumption the variants were unregistered
  and the item was decaying. The user had already done this homework and
  declined; DNS confirms `.com` is registered (parked on non-responding
  nameservers) and `.nl`/`.eu` are free. Closed at the user's direction.
