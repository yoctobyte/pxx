---
prio: 40
---

# Track W (website) — bootstrap the lane: two repos, one board

- **Type:** feature (new lane)
- **Track:** W (website) — NEW LANE, see "Why a new letter" below
- **Status:** backlog — designed 2026-07-12 (user + agent). Not started; the site needs
  creative/UI work — layout, look-and-feel, browser testing — so it wants a dedicated
  session, not a slot at the end of a compiler session.
- **Owner:** —
- **Unblocks:** [[docs-canonical-domain]], [[chore-web-secrets-sops-age]]

## What the website will become
Not a static brochure. Planned surface: docs, landing/download, **bug tracker, forum,
mailing list, wiki, to-dos, video documentation**. Nearly all of it **off-the-shelf plugins**
(Discourse / MediaWiki / a tracker), not code we write. Consequence: the security burden is
*operating* those (patching, spam, moderation, backups), not authoring them.

## Decision: two repos, split on blast radius (NOT on secrecy)

| repo | contents |
| --- | --- |
| **public `frankonpiler`** (this one) | `docs/**` (Track D), the **static site generator** if the site generates from docs, release artifacts + **checksums** |
| **private website repo** | the app, plugin config, DB/mailing-list/forum (PII, sessions, auth), all deploy config, infra-as-code, **encrypted** secrets |

**Rationale, recorded so it is not relitigated:**
- The deciding reasons are **resources + secrets**: a real backend with a DB, a mailing list,
  accounts → PII and credentials. Custom backend code, written fast with no review gate, in a
  public repo, is a genuine vuln-disclosure surface. That alone settles it.
- The reasons that do **NOT** hold, and must not be relied on:
  - *"Public source makes us trivially attackable"* — security by obscurity. Real breaches come
    from secrets in the repo and misconfigured infra, not from readers of the source.
  - *"Private source prevents impersonation/clone sites"* — it does not. The frontend is served
    to the public; a convincing fake is built from the *rendered output* (or from stock
    Discourse/MediaWiki, skinned), never from our repo. (Nuance conceded: a **stateful** fake —
    working forum/wiki/auth — is genuinely more work than `wget --mirror`, so this argument is
    not worthless; it is just not what defends us. See [[feature-release-checksums-repro]] for
    what actually does.)

Publicness is a **feature** for docs and releases: it is what makes them verifiable.

## Why a new letter (and not a separate board)
CLAUDE.md resists new letters — the bar is "a genuinely new *place code lives*". A separate
repo is exactly that, so W qualifies as a **file-lane**, not a work-tag.

But the **tickets stay on this board**, in this public repo. Precedent: **Track T's watcher
runs in its own dedicated clone and is still a track.** Code home ≠ ticket home. One board
means one `progress.sh next`, one priority graph, and — the real reason — **`blocked-by` edges
can cross lanes**. `docs/**` is *published by* the website, so D↔W tickets are inevitable
("site needs a docs frontmatter field", "docs change breaks the site build"). Split boards
give those tickets no home, and the second queue never gets checked.

## The disclosure rule (the one boundary to hold)
A public ticket board describing a live site's internals is itself disclosure. So:

- **Public board (here):** feature / content / design / UI tickets only. "Add a benchmarks
  page", "docs nav broken", "landing copy for v210".
- **Private repo's own issues:** anything security-sensitive — infra topology, incidents,
  vuln reports, dependency CVEs, anything naming a host, a key, or a credential.
- A public W ticket may reference `see private issue #N` and **nothing more**.

## Steps
1. **CLAUDE.md**: add the Track W section (one-liner + the disclosure rule + the gate below).
   Do this when the lane actually starts — a lane other agents can't see doesn't exist.
2. Create the **private website repo**. `.gitignore` + `gitleaks` pre-commit hook from commit
   one, before any config lands. See [[chore-web-secrets-sops-age]].
3. Pick the stack (generator + plugin set). Creative/UI work — needs a real session.
4. Wire the canonical domain: [[docs-canonical-domain]].

## Track W in one line
Own the website: the private app/config/infra repo, plus the site generator if it lives here.
Build/deploy the site; **never touch `compiler/**` or `lib/**`** — like Track D, a compiler or
library gap found while building the site is **filed** in the owning lane, not fixed under W.
Gate = site builds, deploys, and renders (browser-checked). Tickets public per the disclosure
rule above; secrets and infra private.

## Log
- 2026-07-12 — designed. Two-repo split + single board + disclosure rule agreed.
