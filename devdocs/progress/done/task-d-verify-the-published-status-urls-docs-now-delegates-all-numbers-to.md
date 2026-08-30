---
track: D
prio: 30
type: task
status: done
found: 2026-08-30
found-by: frankD
blocked-by: []
summary: "docs/reference/status.md deliberately carries NO figures any more -- it delegates every number to six pxxc.org/status/* URLs. Nothing in this repo checks those URLs resolve or say what the page promises they say, and tools/ has no link checker at all. The page's failure mode moved from 'numbers go stale' (visible, self-correcting) to 'the page promises current numbers and delivers a 404' (invisible from this checkout). Spun out of idea-public-status-page, whose own gap is otherwise discharged."
owner: frankD
---

# The public status page delegates all its numbers off-site, and nothing checks the destination

- **Type:** task — one shippable deliverable, scoped below
- **Track:** D — D owns the prose that makes the promise. The publishing
  machinery is W's and the generators are T's; this ticket touches neither.
- **Found:** 2026-08-30 by frankD, spinning a concrete unit out of
  `idea-public-status-page` [D p25].

## First, the part of the parent that is already done

The parent idea (filed when `status.md` was hand-written prose) says:

> *"Good as a narrative, but the numbers rot — they are a manual snapshot of
> gates that move every day."*

**That is no longer true, and the fix was the parent's own option (a).**
`ce89ff14b` — *"docs(D): stop hand-writing numbers in status.md"* — removed the
figures. The page now opens:

> *"**For current numbers, read the live status pages, not this page.**
> <https://pxxc.org/status/> is generated from the test manager's own output on
> every content pull ... Deliberately no figures — a number written here is a
> number that starts going stale the day it is written."*

So the parent's gap item 1 (publish path) and item 2 (freshness) are both
discharged: the live pages exist, `docs/**` links to them from two files, and
`status.md` is now the stable narrative the idea proposed it become. It even
carries a *"What this page can still get wrong"* section naming the residual rot
direction correctly (prose understates what works, because a feature ships and
the sentence denying it is never revisited).

**The parent's remaining concern is not this.** It also asked that the claims
discipline *"survive templating"* in whatever is auto-generated. Checked:
`tools/twatch_web.py` and `tools/testmgr.py` contain **no** "byte-identical",
"clone", "compatible" or parity language at all — the generated pages carry
numbers, the claims live in `docs/**` prose, and that prose was audited against
CLAUDE.md on 2026-08-29–30. Nothing to do there either.

**Recommend the parent be resolved rather than worked.** Not doing so here: the
dispatch was explicitly to spin out a unit, not to claim the idea.

## What actually remains — the exposure the fix created

Removing the figures was right, and it traded one failure mode for another:

| | before `ce89ff14b` | now |
| --- | --- | --- |
| failure | a number goes stale | a URL 404s, or shows a different project's data |
| visibility | **visible** — a reader who checks sees a wrong number | **invisible from this repo** — the link is syntactically fine |
| self-correcting? | yes, someone eventually re-measures | no, nothing here can see the destination |

That is the better trade. It is not a free one, and the residual has never been
checked once.

### The measurement

- `docs/**` references **six distinct** `pxxc.org/status/*` URLs across two
  files — `/status/`, `/status/conformance/` (twice), `/status/tests/`,
  `/status/benchmarks/` from `docs/reference/status.md`, and `/status/flow/`
  from `docs/targets/nil-python.md:29`.
- Plus three `github.com/yoctobyte/pxx` links, two of them to
  `blob/master/LICENSE.md`.
- **`tools/` contains no link checker** — nothing matching `link`, `url` or
  `href`. `tools/docaudit.py` checks *internal* citations
  (`compiler/…`, `lib/…`) and `tools/docsnip.py` compiles code blocks; neither
  looks at an `http` URL.
- The generated HTML is **not in this checkout**. `twatch_web.py --static`
  writes it inside the watcher's own clone, and `devdocs/progress/tstate/` here
  holds only the TSV/JSON inputs. So there is no local artefact to diff against
  either.

`status.md` does not merely *link* to those URLs — it **delegates its entire
numeric content** to them. If `/status/conformance/` is missing, the public
compatibility page has no figures and no working pointer to any, while
explicitly telling the reader that is where the figures are. That is strictly
worse than the hand-maintained snapshot it replaced, and it is the one outcome
nobody would notice from inside the repo.

## The deliverable — one thing

**A link check over `docs/**`, wired into Track D's gate.** Modelled on the two
checkers already shipped for this lane, and deliberately no larger:

1. Extract every `http(s)://` URL from `docs/**` (the extractor must skip
   markdown artefacts — a naive regex picks up ``https://`` from inline code
   fences, and `example.com` appears twice as an intentional placeholder).
2. Request each one; report non-2xx, with the file and line.
3. For the `pxxc.org/status/*` set only, assert the response actually looks like
   the report it is promised to be — a conformance page containing pass/fail
   counts, not a landing page or a redirect to one. **This is the half that
   matters**: a 200 that renders the wrong thing is exactly as bad as a 404 and
   a plain status check will not see it.
4. Run it from `docs/` work, not from every gate — it is the only check in this
   lane that needs the network, and it must degrade to SKIP (never FAIL) when
   offline, or it converts a lane that works on a train into one that does not.

## Scope notes

- **Not** a website change. If a URL is wrong, the fix is either the link in
  `docs/**` (D) or the publish path (W) — this ticket only makes the breakage
  visible, and files what it finds into the owning lane.
- **Not** a general docs link-farm. Ten URLs across 41 files; the value is
  entirely in the six that carry delegated content, and the GitHub ones are
  nearly free to include.
- The offline-SKIP rule in step 4 is load-bearing, not politeness. A network
  check that hard-fails is a check people delete.

## Gate
The checker runs, reports the six status URLs and the GitHub links, and skips
cleanly with no network. No compiler build, no `lib/**`.

## Done — `tools/doclinks.py`, 2026-08-30

**Every URL was verified by fetching it, not by reading what the doc says it
links to.** All eight distinct external links in `docs/**` resolve, and all five
content-marker assertions pass:

```
docs: 13 external link(s), 8 distinct
  ok   https://github.com/yoctobyte/pxx
  ok   https://github.com/yoctobyte/pxx/blob/master/LICENSE.md
  ok   https://pxxc.org
  ok   https://pxxc.org/status/              [backlog resolved]
  ok   https://pxxc.org/status/benchmarks/   [fib sieve]
  ok   https://pxxc.org/status/conformance/  [pass fail]
  ok   https://pxxc.org/status/flow/         [filed closed]
  ok   https://pxxc.org/status/tests/        [GREEN RED]
checked 8, BROKEN 0
```

**So the feared failure is not occurring** — `status.md`'s delegation is honest
today. `/status/conformance/` carries real per-category pass/fail/skip counts
across 25 `t*` categories, `/status/tests/` the four watcher hosts with SHAs and
GREEN/RED verdicts, `/status/benchmarks/` per-`-O`-level timings against FPC,
`/status/flow/` the filed-vs-closed curves. That does not retire the check; it
establishes the baseline the check defends.

### All four paths were exercised, not just the green one

Publishing an untested failure path would repeat the defect found the same
morning in the fact sheet — a command nobody ran reads as verification.

| path | how | result |
| --- | --- | --- |
| green | the real `docs/**` | 8 ok, exit 0 |
| 404 | a fabricated `/status/definitely-not-a-page/` | `BROKEN … HTTP 404`, exit 1 |
| **200-but-wrong** | marker overridden to an impossible word | `BROKEN … reachable but missing …`, exit 1 |
| offline | unreachable-probe timeout | `SKIP … this is not a failure`, exit 0 |

The third row is the one the tool exists for and the one a plain status check
cannot see. The fourth is why it will still be here in a month.

Also confirmed ignored, both of which would otherwise be reported forever: the
two `example.com` placeholders, and the ``https://`` fragment a naive regex
lifts out of an inline code fence.

### One divergence, reported not fixed

The published dashboard says **338 backlog**; `tools/factsheet.sh` says **351**.
Both are defensible — factsheet adds `backlog_new/` (13), the dashboard appears
to break those out separately alongside "20 experimental". Not a defect, and not
D's call, but two public surfaces answer "how big is the backlog" differently and
whoever owns the generator (T/W) should decide which is meant. Filed here rather
than as its own ticket because it is one sentence and may be intentional.

### Not done, deliberately
Not wired into a gate. It is the only check in this lane needing the network, it
takes ~8 round trips, and its value is weekly rather than per-commit — running it
from `docs/` work is what the ticket asked for and what the exit codes support.

**Resolves** the spin-out. The parent `idea-public-status-page` is separately
discharged (see this ticket's opening section) and is a `resolve`, not work.

## Provenance
Spun out of `idea-public-status-page` [D p25] on 2026-08-30. Every claim above
about `status.md`'s current content is from the file at `HEAD`, and the
"no claim language in the generators" finding is from grepping
`tools/twatch_web.py` and `tools/testmgr.py` directly — not from the parent
ticket's description, which is two rewrites out of date and is the reason this
spin-out reads the way it does.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
