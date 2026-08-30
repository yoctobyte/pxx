
---

## CLOSED 2026-08-30 — returned UNSPENT, and the grant's own premise was stale

`tools/progress.py` is released; last write to it is still the coordinator's.
pxx-a5 never touched it. The check is built and landed in **`sync.sh`**
(`c1a8e092c`), which is the better home.

**The grant was filed on a retracted number.** It cites "3 of 681", and
`72538cc79` — pushed *before* the grant — had already closed the source ticket as
`rejected/`: the 3-of-681 came from an ad-hoc test that counted a ticket merely
discussing a `commit range 8fb3f776..b3fd1c76` as cited. Under the house definition
(`CITATION_RE` + a line-start key, what `_audit_citations` already uses):

| window | resolved | uncited |
| --- | ---: | ---: |
| pre-2026-08 | 1123 | 456 (41%) |
| 2026-08-26..31 (freshest six days) | 328 | **31 (9%)** |

**The freshest window IS the date floor, and it still yields 31** — so caution 2,
pxx-a5's own, does not survive its own data. As a standing `check` over the tree
this was exactly the muted guard its cautions were written to prevent.

**What changed is the SCOPE, not the check.** The same 31 findings are worthless as
a standing report and valuable *one at a time, addressed to the person who just
resolved the ticket, at the moment fixing it costs one line.* So it sits beside
`verify_citations_landed` over `manifest_resolved`. That dissolves caution 2
entirely — **there is no date floor to get wrong, because "this push" is the floor.**

Calibrated live: last 400 commits touching a resolved bucket = **469 resolutions,
43 would nudge (9%)**. **23 of the 43 are `regression-`/`decide-`/`grant-` slugs
whose resolution IS a verdict** — the watcher closes regression tickets from tstate,
a decision closes when the user rules, a grant closes when it is returned, as this
one just was. That is **caution 3, in live data, at 53% of findings.** Excluded by
prefix: **19 of 469 — 4%**, one per twenty-five, every survivor a `bug-`/`feature-`
that changed code and cited nothing.

`--no-renames` on `manifest_resolved` is load-bearing: a `git mv backlog/ → done/`
reports as **R**, so `--diff-filter=A` would never see the move the check is about.
Guard: `sync_citation_guard_devtest.py`, **36 guards, 0 FAIL** (was 24).
