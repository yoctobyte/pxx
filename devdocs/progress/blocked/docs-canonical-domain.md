---
prio: 45
---

# Canonical domain in the docs

- **Type:** docs
- **Track:** D (docs) — with a Track W follow-on
- **Status:** **blocked** — needs the domain name from the user (it is registered; the agent was
  not told which). Opened 2026-07-12.
- **Owner:** —
- **Related:** [[feature-web-track-w-bootstrap]], [[feature-release-checksums-repro]]

## Why
**The domain is the trust anchor.** Against impersonation it beats every technical measure:
people check the address bar, not the source repo. Naming it canonically — in the docs, the
README, the installers, the release notes — is what makes a fake *look wrong* to a user who has
seen the real one. Cheap, high leverage, do it early so it propagates everywhere by default.

## Scope
1. Wire the domain as canonical across `docs/**`: install/download links, landing copy, README.
2. Installer/bootstrap scripts point at the canonical URL (dovetails with
   [[feature-release-checksums-repro]] — fetch canonical, verify checksum, then run).
3. **Register the obvious typosquats** and the `.com`/`.org`/`.dev` variants of the name. Cheap
   insurance; the single highest-leverage anti-impersonation move available. (User action.)
4. HTTPS + HSTS on the live site; a canonical link element in the published pages. (Track W.)

## Blocked on
The domain name. Unblock = user supplies it, then this is a same-session job.

## Log
- 2026-07-12 — opened, blocked on the name. Domain is registered per the user.
