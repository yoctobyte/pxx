---
prio: 45
---

# Canonical domain in the docs

- **Type:** docs
- **Track:** D (docs) — with a Track W follow-on
- **Status:** **blocked** — the domain is **`pxxc.org`** (registered 2026-07). Blocked not on the
  name but on the site being **live**: publishing a canonical URL that does not resolve is worse
  than publishing none — a 404 on our own link teaches the first visitors the domain is dead.
  Unblock = site serves something real. Opened 2026-07-12.
- **Owner:** —
- **Related:** [[feature-web-track-w-bootstrap]], [[feature-release-checksums-repro]]

## Why
**The domain is the trust anchor.** Against impersonation it beats every technical measure:
people check the address bar, not the source repo. Naming it canonically — in the docs, the
README, the installers, the release notes — is what makes a fake *look wrong* to a user who has
seen the real one. Cheap, high leverage, do it early so it propagates everywhere by default.

## Scope

### Do NOW (independent of the site being live) — user action
**Register the variants of `pxxc`.** This is the one item that gets *harder* with time: once the
project is visible, squatters watch for exactly this gap.
- **`pxxc.com`** — priority. A compiler whose canonical home is `.org` while `.com` sits free is
  the classic impersonation setup: someone else's page can outrank ours and we'd be arguing
  rather than owning.
- **`pxxc.nl` / `pxxc.eu`** — the jurisdiction hedge. `.org` is PIR (US-controlled); a ccTLD is
  not reachable by a US action. See [[feature-web-tracker-and-host-portability]].
- Total ~€30/yr. Point them all at the same site; `pxxc.org` stays canonical.

### Do WHEN LIVE
1. Wire `pxxc.org` as canonical across `docs/**`: install/download links, landing copy, README.
2. Installer/bootstrap scripts point at the canonical URL (dovetails with
   [[feature-release-checksums-repro]] — fetch canonical, verify checksum, then run).
3. HTTPS + HSTS; a `<link rel="canonical">` in the published pages. (Track W.)
4. Publish the release-signing key fingerprint on the site (second publication point — trust is
   key continuity + publication).

## Blocked on
**The site being live.** The name is known (`pxxc.org`); it is deliberately NOT yet written into
`docs/**` because it does not resolve. Unblock = the site serves real content; then this is a
same-session job.

## Log
- 2026-07-12 — opened. Domain is `pxxc.org`, registered but not live. Blocker restated: not the
  name, but the site. Variant registration split out as a do-now item — it does not depend on the
  site and it decays with time.
