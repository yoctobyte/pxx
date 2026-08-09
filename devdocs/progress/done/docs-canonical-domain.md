---
prio: 45
---

# Canonical domain in the docs

- **Type:** docs
- **Track:** D (docs) — with a Track W follow-on
- **Status:** done
  went live, wired 2026-08-09. The old blocker was never the name but the site:
  publishing a canonical URL that does not resolve is worse than publishing
  none, because a 404 on our own link teaches the first visitors the domain is
  dead.
- **Owner:** trackW-agent
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
1. **DONE 2026-08-09.** `pxxc.org` wired as canonical across `docs/**`: README
   header + Documentation section, `docs/index.md` footer, and an **Official
   sources** block on `docs/install/index.md` naming the site and the repo as
   the only two, since that page is where someone about to install looks.
2. **Nothing to point at — deferred to [[feature-release-checksums-repro]].**
   `install.sh` runs *inside* an existing checkout; it fetches no compiler. With
   no binary release channel there is no download URL to canonicalise, and
   inventing one would publish a dead link — the exact failure this ticket was
   blocked on. Reopen when releases exist.
3. **DONE 2026-08-09 (Track W).** `<link rel="canonical">`, OG URLs, sitemap and
   robots all already pointed at `https://pxxc.org`. HSTS was the gap: now
   `max-age=63072000`, no `includeSubDomains`, no preload, emitted per nginx
   location (`add_header` does not merge — a server-level one would have been
   dropped by every location and still tested fine). Rolled out at 300s and
   verified on apex, www, `/status/` and `/static/` before the long value.
4. **Cannot do — no key exists yet.** Publishing a fingerprint is meaningless
   until [[feature-web-tracker-and-host-portability]] creates the signing key.
   That ticket already owns "fingerprint published in >=2 places"; the site is
   one of the two, so this needs no separate tracking here.

## Log
- 2026-08-09 — items 1 and 3 done; 2 and 4 are not ours to finish and are
  carried by the two related tickets. The **do-now variant registration is still
  open and still decaying**, so it is re-filed as its own ticket rather than
  buried in a resolved one: [[chore-register-pxxc-domain-variants]].
  HSTS caveat worth repeating: it is not revertible from the server, so pxxc.org
  is https-only for two years for anyone who has visited.
- 2026-07-31 — unblocked: pxxc.org verified live and serving.
- 2026-07-12 — opened. Domain is `pxxc.org`, registered but not live. Blocker restated: not the
  name, but the site. Variant registration split out as a do-now item — it does not depend on the
  site and it decays with time.
- 2026-08-09 — resolved, commit PENDING-COMMIT.
