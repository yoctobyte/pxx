---
slug: bug-w-status-benchmarks-503s-while-every-sibling-page-serves
track: W
type: bug
prio: 40
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "`https://pxxc.org/status/benchmarks/` has answered 503 for hours while `/`, `/status/` and `/status/tests/` all serve 200 — so it is one deployed page, not the site. It was verified working on 2026-08-30 with its content marker `[fib sieve]` by task-d-verify-the-published-status-urls, which makes this a regression against a checked baseline rather than a link that was never right. `docs/reference/status.md:16` cites it correctly and DELEGATES its numbers to it, so a reader is told where the timings are and gets a 503. Docs deliberately unchanged: removing the link would turn Track D's gate green by deleting the only thing pointing at the outage."
---

# `/status/benchmarks/` 503s while every sibling serves

Measured 2026-09-05 ~18:30 UTC, from plexus, with plain `curl` and again with
`tools/doclinks.py` — two instruments, and repeated across several hours:

```
https://pxxc.org/                     200
https://pxxc.org/status/              200
https://pxxc.org/status/tests/        200
https://pxxc.org/status/benchmarks/   503   (twice in a row, 25s timeout)
```

**Only the leaf fails.** The siblings responding rules out DNS, TLS, routing and
the host being down, which is why this is filed as a page rather than reported as
"the site is broken".

## It is a regression against a verified baseline, not an unchecked link

[[task-d-verify-the-published-status-urls-docs-now-delegates-all-numbers-to]]
fetched all eight external URLs on 2026-08-30 and recorded:

```
  ok   https://pxxc.org/status/benchmarks/   [fib sieve]
```

— a 200 whose body contained the expected content markers. So the page existed,
served, and carried per-`-O`-level timings against FPC six days ago.

## Why it matters more than a broken link usually would

`docs/reference/status.md` carries **no figures at all** by design (`ce89ff14b`)
and delegates every number to these URLs. Line 16 tells the reader that
`benchmarks` is where the timings are. The page therefore promises current
numbers and delivers a 503 — which is exactly the failure mode the prior ticket
was filed to defend against, arriving for the first time.

## Docs deliberately NOT changed

`docs/reference/status.md:16` cites the page correctly; the link is not the
defect. Removing or rerouting it would take Track D's external-link gate to
green **by deleting the only thing currently pointing at the outage** — a green
bought by removing the observation, which is the same move as fixing a false RED
by deleting the guard.

So Track D's `doclinks.py` will keep reporting exactly one BROKEN row until this
is fixed or the page is deliberately retired. That row is doing its job.

## Routing

Filed to W because the fix is the publish path or the host, not this repo's
prose. Noted for whoever takes it: `~/pxx-website` was last committed
2026-08-29, and a 503 on one deployed page while its siblings serve looks more
like generation or infra than a repo change. frank-coordinator independently
reproduced the four rows above and escalated to the owner the same evening,
since nobody was on W that night.

**If this is still red with no movement, say so again rather than absorbing it.**
A standing red everyone has learned to expect is how a real outage becomes
wallpaper — and this one is invisible from inside the checkout by construction.
