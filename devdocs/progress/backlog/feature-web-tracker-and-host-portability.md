---
prio: 45
blocked-by: [feature-web-track-w-bootstrap]
---

# Public tracker on GitHub + host-portability rule (nothing lives only in a service)

- **Type:** feature (infra / release + community)
- **Track:** W (website) — with Track A touchpoints (releases, CI)
- **Status:** backlog — designed 2026-07-12.
- **Owner:** —
- **Blocked-by:** feature-web-track-w-bootstrap
- **Related:** [[feature-release-checksums-repro]], [[docs-canonical-domain]]

## Two trackers, only one is a question
- **Internal dev work** — stays `devdocs/progress/**`, files in git. Already zero lock-in,
  works offline, drives the agent `next → claim → resolve` loop and the priority graph.
  **Never migrate this to GitHub Issues** — it would lose the loop and gain nothing. Decision
  recorded so it is not relitigated.
- **Public bug reports from users** — a different population (drive-by reporters, no repo
  access, want notifications). **Use GitHub Issues.** GitHub eats the spam/moderation/backup
  burden for free, and contributors already have accounts — signup friction is most of the
  difference between 5 reports and 50. Self-hosting a tracker is a permanent ops cost and a
  spam magnet.
- Forum: **GitHub Discussions** first. Stand up Discourse only if the community outgrows it.

## The rule that makes the dependency reversible
> **Never let a service hold data that exists only there.**

Judge every hosted feature by that single test:

| feature | git-native form? | verdict |
| --- | --- | --- |
| repo / code | yes — git is *designed* distributed | safe; it IS the escape hatch |
| releases + checksums | yes, if artifacts are reproducible and **we** hold the signing key | safe |
| wiki | yes — it is a git repo | safe |
| **Issues / Discussions** | **no** — API-only | **needs the export job (below)** |
| Actions (CI) | proprietary YAML | keep it a **thin wrapper** over `make` / `testmgr.py` |
| Projects / Packages / Pages | no | avoid |

**Why this is not paranoia:** GitHub is Microsoft, US jurisdiction. It froze accounts in Iran,
Syria and Crimea in 2019 on sanctions grounds — private repos inaccessible, no appeal, nothing
to do with the users' conduct. "We lose access for reasons that have nothing to do with us" is a
documented failure mode. The answer is not to avoid GitHub (it is a good service and we are
staying); it is to keep leaving cheap.

## We are already most of the way there
- **Test infra is local-first** — `testmgr.py` + the twatch daemon run on our own hardware. CI
  is at most a convenience wrapper around `make`. Most projects have this backwards.
- **Dev board is files in git.** No migration needed.
- **We own the domain** — the portable *identity*. Hosting can move; the URL people know does
  not. (This is why [[docs-canonical-domain]] matters: independence, not branding.)

## The signing key is the deep answer
If **we** sign the release checksums with **our** key, the artifact is verifiable **no matter who
hosts it** — mirror it to Codeberg, S3, anywhere; verification still passes. That is what makes
hosts *interchangeable*. **Never let GitHub sign for us** (do not build on their attestation
service). See [[feature-release-checksums-repro]].

**Self-signed, no CA — cost €0.** Trust comes from **key continuity + publication** (fingerprint
in the repo, on the site, in release notes), exactly as every Linux distro does it. Nobody is
verifying a legal identity; they are verifying that today's binary is signed by the same key as
last year's. Continuity *is* the identity.

**Paid code-signing certs solve a different problem — OS gatekeepers — and are DEFERRED:**
Windows Authenticode (~€100–400/yr, silences SmartScreen) and Apple notarization (€99/yr) are
only needed when we ship consumer-facing Windows/macOS installers. For a compiler shipped to
developers on Linux they buy nothing. Do not conflate them with release signing.

## Scope (three cheap moves, ~an afternoon total)
1. **Continuous mirror** — add extra push URLs so every push goes everywhere:
   `git remote set-url --add --push origin <codeberg-url>` (+ a self-hosted bare repo).
   Codeberg = German non-profit, Forgejo, EU jurisdiction — the natural hedge. Migration then
   becomes a DNS change, not a project.
2. **Issue export job** — scheduled `gh api` dump of issues + comments to JSON/Markdown,
   committed to git. From day one. Issues are the ONLY GitHub-native data we create, so this is
   the whole exposure. Turns GitHub into a *frontend*, not the system of record.
3. **Keep CI a thin wrapper** over `make` / `testmgr.py`. Already true — write it down so nobody
   "improves" it into Actions-specific YAML.
4. Optional, ~€10/yr: register a **ccTLD** (`.nl` / `.eu`) alongside the `.com`/`.org` — those sit
   under US-controlled registries (Verisign/PIR). Point both at the same site, one canonical.

## Acceptance
Mirror push configured and verified; issue-export job runs and its output is committed; CI
invokes `make`/`testmgr.py` and nothing GitHub-specific; the release signing key is ours and its
fingerprint is published in ≥2 places.

## Log
- 2026-07-12 — designed. GitHub stays; the point is that leaving must remain cheap.
