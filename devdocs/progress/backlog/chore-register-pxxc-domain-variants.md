---
prio: 55
---

# Register the pxxc domain variants (.com, .nl, .eu)

- **Type:** chore (user action — needs a card, not an agent)
- **Track:** W (website)
- **Status:** backlog — split out of [[docs-canonical-domain]] on 2026-08-09 so
  it does not get resolved along with the docs wiring it has nothing to do with.
- **Owner:** — (the user; no agent can buy a domain)
- **Related:** [[docs-canonical-domain]], [[feature-web-tracker-and-host-portability]]

## Why this is the item that decays

Everything else on the canonical-domain ticket got *easier* once the site went
live. This one gets **harder**: registration is first-come, and the moment the
project is visible enough to be worth impersonating is exactly the moment the
names stop being available. It costs ~€30/yr to close permanently.

- **`pxxc.com`** — the priority. A compiler whose canonical home is `.org` while
  the `.com` sits unregistered is the textbook impersonation setup: someone
  else's page can outrank ours on the project's own name, and then we are
  arguing rather than owning.
- **`pxxc.nl` / `pxxc.eu`** — the jurisdiction hedge. `.org` is PIR, which is
  US-controlled; a ccTLD is not reachable by a US action. Same reasoning as the
  host-portability ticket: the domain is the portable identity, so it should not
  have a single legal chokepoint.

## Scope

1. Register `pxxc.com`, `pxxc.nl`, `pxxc.eu`.
2. Point them at the same site. `pxxc.org` stays canonical — the others redirect,
   they do not serve. Serving the same content on four names splits the trust
   anchor instead of widening it, and every extra origin is another thing to
   keep in step.
3. Keep them out of the HSTS policy already on `pxxc.org` unless they get their
   own; the header deliberately carries no `includeSubDomains`.

## Acceptance

All three registered and renewing, each redirecting to `https://pxxc.org`, and
the registrar/renewal detail recorded wherever the pxxc.org registration already
is (private — not on this board, per the disclosure rule).

## Log
- 2026-08-09 — split out of [[docs-canonical-domain]], which resolved its own
  docs and HSTS items the same day. Filed separately because burying a decaying
  user action inside a resolved ticket is how it gets lost.
