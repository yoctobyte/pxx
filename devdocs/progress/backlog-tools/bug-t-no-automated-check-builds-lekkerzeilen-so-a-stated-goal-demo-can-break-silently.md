---
track: T
prio: 55
status: open
type: bug
blocked-by: []
summary: "lekkerzeilen is a stated goal (`have lekkerzeilen compile under nilpy as demo`) and NOTHING checks that it compiles. Demonstrated 2026-09-20: a compiler commit stopped it building and every existing signal stayed green — gate.sh quick GREEN, self-host fixedpoint converged, the commit's own fixtures passed, no tier covers it. It was found only because a seat happened to need the demo as an A/B subject for an unrelated measurement, which is luck and not a process; absent that it stays broken until somebody runs it by hand. THE COST IS BOUNDED AND KNOWN: a compile is ~125 s and the failure mode is fast — the break above errors in ~19 s — so a check need not pay the full build to catch this class. NOT a request to add lekkerzeilen to a tier: it lives in another repo and the tier rules forbid that. The decidable question is where a demo-build signal belongs given that constraint, which is why this is filed rather than fixed."
---

# Nothing checks that lekkerzeilen still compiles

Found while measuring build time, not by any instrument built to notice it. See
`urgent/bug-n-0c508e507-breaks-lekkerzeilen-heapq-resolution-...` for the break
that exposed it and `devdocs/perf/lekkerzeilen-build-time.md` for the timings a
check could be budgeted against.

**What makes this its own ticket rather than a line on that one:** the break will
be fixed within the hour by its author. The absence of any signal will not.
