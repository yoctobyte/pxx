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


## AMENDED 2026-08-30 — the grant named the wrong tree, and is extended to four files

**`devdocs/dev/` and `devdocs/developer/` are two different trees** — 53 and 58 top-level
pages respectively. This grant said `devdocs/dev/*.md`. frankD's sweep covered
`devdocs/developer/`, which was outside it.

**Nothing was violated**: the sweep was audit-only and frankD edited nothing there, filing a
ticket for the lane instead. Reading is not gated. But the grant was wrong on its face and
is corrected here rather than left to be discovered — a grant that names the wrong scope is
the same defect class as a hold enforced by a number.

### Extended, narrowly, to four named files

`devdocs/developer/` is not named anywhere in CLAUDE.md — `docs/**` is Track D's, and
`devdocs/dev/**` is called out as A/B's. `devdocs/developer/**` falls to A/B by the same
logic and is, in practice, **unowned**. That is precisely the condition frankD's own finding
predicts rot in.

**frankD may edit these four files, for this one purpose:**

| file | line | what it prescribes |
| --- | --- | --- |
| `todo-dynamic-arrays.md` | 219 | *"## Verification Gate — Run:"* → `make test`, then the nilpy suite |
| `threads-todo.md` | 198 | *"## 7. Exit Gate — Each phase must pass:"* → *"1. Default `make test`."* |
| `nil-python.md` | 83 | *"## Regression Tests"* → the nilpy suite |
| `esp32-support.md` | 86 | *"Run + validate"* → `make test-esp-bare` |

**Why these four and not the sweep:** they are the live supply of the exact behaviour
`.claude/hooks/no-full-suite.sh` was built to stop. The hook's own header comment records
that an agent *"reached for [the nilpy suite] twice in one session"* — **these pages are
where that instruction still lives.** An agent following them hits REFUSED with no idea
why, because nothing on the page knows the rule changed. The hook is in `.claude/` and is
owned; the instruction is in an unowned tree; nobody connected them.

**This is not a documentation-tidiness item. It is a live defect with a measured victim.**

Scope of the edit: replace the denied command with the per-fix loop from CLAUDE.md and a
pointer to it. **Do not touch `.claude/**` or the hook** — that boundary does not move, and
the fix is on the docs side by construction. `threads-todo.md` needs care: items 2 and 3 of
its ladder (self-host fixedpoint; the same path under `--threadsafe`) are **still correct**
and only item 1 is superseded, so annotate rather than delete the section.

**Not extended to anything else in that tree.** The ~40 unclassifiable pages stay
untouched: frankD is right that correcting a record falsifies history, that it cannot tell
record from live reference without the git log, and that classification must come first.
Its own scoping holds — 24 of 58 pages *mention* a denied command and only these four
*prescribe* one; `project-state.md:155` looks prescriptive to a grep and is a past-tense
record. **The grep overstates by 6x and the sweep must not be run on the grep.**

## Discharge record — 2026-08-30, frankD

**The sweep this grant authorises was performed under the grant's first issue**
(the verbal one this ticket retro-files), earlier the same session. It is done,
and this ticket's own header says why the confusion is possible: *"second issue;
the first was given in conversation earlier the same session and should have been
filed then."* An unfiled authorisation is invisible to the board, so the board
re-offers the work — which is the same defect the grant was filed to fix, arriving
from the other side.

**What the sweep covered:** 42 live references of the 53 top-level `.md` (the rest
are session records, which are never edited). 13+ pages corrected across ~20
commits; three tickets filed into owning lanes; `tools/docaudit.py` shipped with
five modes. The findings this grant cites as its own rationale — the `--threadsafe`
scope wrong in two pages, six superseded gate rules, the `-O0` claim asserting the
**inverse** of the 2026-08-19 incident's lesson — are that sweep's output.

**Residual worked on this pass, and it is a null result.** One lens was new: *a
false limit is quieter than a false fix and survives longer.* Applied to every
limitation sentence in `devdocs/dev/*.md`. **All passed** — see the new subsection
in `devdocs/dev/README.md` §4 for the finding that fell out of it: the three
surviving limits each name the instrument that gets past them, so the cheap
sweepable question is not *"is this limit true?"* but *"does it say what to do
instead?"*. A caveat that ends in a full stop is the one to check.

**Not resolved here.** A permission slip is not a unit of work, and the same
coordinator noted earlier tonight that this ticket ranking at all is the board
failing to distinguish "unblocked" from "has work in it". Closing it is the
grantor's call, not the grantee's — a grantee who resolves their own authorisation
is marking their own homework.
