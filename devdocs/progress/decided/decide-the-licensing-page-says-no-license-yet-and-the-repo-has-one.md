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

---

## RESOLVED 2026-08-30 — option 1, superseded. The split is final.

> *"we decided about the license long ago. i think that was stale info."*
> — owner, 2026-08-30

And "long ago" is checkable: `done/task-license-mpl2-rollout` carries a
**"Decision (final)"** section dated **2026-07-02**. So the page was eight weeks
stale, not the six the ticket estimated from file mtimes — the mtime dates the
last *edit*, and the decision it missed is older than that.

### How the page survived the rollout, which is the reusable part

That same ticket's step 3 reads *"Update `README.md` License section (currently
says 'no license yet')"*. The README was updated. **This page said the same
thing and was not on the list.** A rollout checklist enumerates the files its
author knew about, so the page that most needed changing was the one nobody
remembered — and it then sat for eight weeks, linking to `LICENSE.md` as *"the
current public notice"*, i.e. pointing at its own refutation.

The general form, worth having when the next repo-wide claim changes: **a
checklist covers what its author recalled, so the search that finds the rest has
to be a grep for the CLAIM, not a list of files.** Grepping `no license
yet|remains unlicensed|not open source yet|all rights reserved` across
`docs/ devdocs/ README.md` after the fix returns only this page and the rollout
ticket's own historical line — so the tree is clean now, and that grep is what
should have run in July.

### What was done

`devdocs/developer/licensing-concerns.md` rewritten as a superseded record, not
deleted:

| section | disposition |
| --- | --- |
| Current Position: No License Yet | **HISTORICAL** |
| Authorship, AI Assistance, And Future Forks | **STILL LIVE** — with one struck paragraph |
| Source-Available, Not Open Source | **STILL LIVE** — background, and the distinction is still correct |
| Existing License Families To Consider | **HISTORICAL** |
| Practical Recommendation For The Public Release | **HISTORICAL** — the actively misleading one |

**Not deleted, deliberately.** The reasoning behind the zlib/MPL split is worth
more than the file it sits in — the runtime is zlib *because it is embedded into
every binary the compiler produces*, so programs built with pxx carry no
obligations from the toolchain. Deleting the deliberation would leave the
conclusion with no recorded why, and "why not PolyForm?" is a question a reader
will actually ask.

One paragraph inside a live section was struck rather than kept: *"This is a
statement of intent, not a present license grant. The current repository remains
unlicensed until a license or written permission says otherwise."* A fork under
MIT/BSD/GPL no longer needs permission asked first. The paragraphs around it
about a fork's **responsibility** for its own license and claims are unaffected
and still the intent.
