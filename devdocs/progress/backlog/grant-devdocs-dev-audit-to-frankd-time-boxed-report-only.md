---
slug: grant-devdocs-dev-audit-to-frankd-time-boxed-report-only
track: D
prio: 50
type: grant
status: open
found: 2026-08-30
---

# GRANT: `devdocs/dev/*.md` → frankD, audit-only, time-boxed

**Granted 2026-08-30** (second issue; the first was given in conversation earlier the same
session and **should have been filed then** — see the failure note below).

`devdocs/dev/**` is not Track D's ground by default: D owns `docs/**`, the public Markdown
the website publishes. This grant opens the **internal reference docs** to D for an audit,
because D has just demonstrated the exact capability the job needs and found the highest-
value documentation defect of the night.

## Scope

- **Read and correct prose in `devdocs/dev/*.md` only.** Never `compiler/**`, never
  `lib/**`, never `.claude/**`, never `CLAUDE.md`.
- A code or gate defect the audit *finds* → **ticket in the owning lane**, hand off. This
  grant does not extend to anything the sweep discovers.
- Expires when the sweep is written up. The default boundary is restored the moment it is
  done; it is not a standing widening of Track D.

## Why this ground, and the ordering that follows

frankD's own measured finding, from auditing both sides tonight:

> **accuracy tracked who is accountable for the page, not how many people read it.**

`docs/**` — fewer readers, all of whom could check it less easily — was the **more**
accurate of the two. The internal reference docs, read constantly by agents who act on
them, were the ones carrying false claims: a `--threadsafe` scope wrong in two pages, six
stale gate references, and a `-O0` claim asserting the **inverse** of the fact whose
falsity produced the 2026-08-19 incident.

That inverts the many-eyes assumption, and it sets the sweep's ordering: **go at the pages
nobody owns, not the pages most cited.**

## The failure this grant is filed to prevent

The first grant was given in conversation and never written down. Hours later the
coordinator — with no memory of issuing it — **instructed frankD to file and hand off work
frankD had already completed under that grant**, and framed it as a boundary correction for
a violation that had not occurred, on ground the coordinator had itself opened.

frankD checked before re-filing and declined to file the duplicate.

The rule was already written (`coordinator-operating-rules`, rule 5): **an authorisation is
a finding about what is permitted, and a finding is recorded when it is on master.** It was
broken on the very grant it later contradicted. The coordinator's context is destroyed and
rebuilt continuously while the work it tracks continues, so this is the standing condition
of the seat rather than a lapse — which is exactly why the remedy is a file and not a
resolution to remember.
