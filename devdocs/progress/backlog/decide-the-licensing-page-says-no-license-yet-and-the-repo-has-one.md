---
slug: decide-the-licensing-page-says-no-license-yet-and-the-repo-has-one
track: U
prio: 60
type: decide
status: open
found: 2026-08-30
---

# DECIDE: `licensing-concerns.md` says "No License Yet"; the repo root carries LICENSE

`devdocs/developer/licensing-concerns.md:10` is headed **"## Current Position: No License
Yet"**. The repo root carries `LICENSE` and `LICENSE.md`, and the README states a
per-component split — **zlib / 0BSD / CC BY 4.0**.

Found by frankD during an audit-only sweep of the unowned `devdocs/developer/` tree.
**Flagged, not fixed, and routed here rather than to a docs edit** — correctly.

## Why this is yours and not a documentation task

Every other staleness in that sweep is an engineering cost: an agent wastes ten minutes, a
gate is described wrongly, a "not implemented" claim is disproved by compiling. **This one
is not.** A page stating the project has no license, while the project has three, is a
claim about what other people may legally do with the code — and it is the kind of claim
that is read by exactly the sort of person you do not want reading a wrong one.

**A launch is precisely when someone reads it.**

## The fork

The question is not "should the page be updated" — plainly yes. It is **what the page
should now say**, and that is not derivable from the tree:

1. **It is superseded** — the position was reached, the LICENSE files are the answer, and
   the page becomes a historical record with a `Status (date): superseded` line.
   *(Likeliest, but it is your call to confirm the split is final.)*
2. **It is live and the concerns are open** — the LICENSE files are provisional, the
   concerns the page raises still stand, and it needs updating rather than closing.
3. **The split itself needs revisiting before launch** — in which case this is real work,
   not a docs fix.

I cannot tell which from the repository. The LICENSE files exist; whether they represent a
settled position or a placeholder is a fact only you hold, and guessing it into a public-
adjacent page is exactly the class of guess Track U exists to prevent.

## Method note for whoever picks up the surrounding sweep

frankD's grep for the hook-denied commands **tripped the hook itself**, because the hook
scans command *text* and does not care that the command is inside a search pattern. Fourth
false positive of that shape in one session. **The tree cannot be swept with the obvious
command**, and a REFUSED there is an artefact of the search, not a finding.
