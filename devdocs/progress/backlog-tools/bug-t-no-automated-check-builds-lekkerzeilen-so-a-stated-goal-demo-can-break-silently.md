---
track: T
prio: 55
status: open
type: bug
blocked-by: []
summary: "lekkerzeilen is a stated goal (`have lekkerzeilen compile under nilpy as demo`) and NOTHING checks that it compiles — no tier, no gate row, no smoke target. THE WORKED EXAMPLE THIS WAS FILED ON WAS MY OWN ERROR and is withdrawn: I reported a compiler regression on 2026-09-20 and it was a relocated binary, not a defect (see rejected/bug-n-0c508e507-...). The gap stands on the ABSENCE, which needs no incident: at the time of filing, the only way anyone learns the demo stopped compiling is a human running it by hand. Cost is bounded and known — a clean compile is ~125 s and a resolution failure errors in ~19 s, so a check need not pay the full build to catch that class. NOT a request to add it to a tier: it lives in another repo and the tier rules forbid that, which is exactly what makes this a question rather than a task. Note the irony recorded honestly: the absence of a check is also why my own false alarm took four people-hours to settle — with a green demo row I would have known in one command that nothing was broken."
---

# Nothing checks that lekkerzeilen still compiles

Found while measuring build time. **The break that prompted this did not exist** — see
`rejected/bug-n-0c508e507-...` for my error. The gap is real regardless:
nothing checks the demo builds. `devdocs/perf/lekkerzeilen-build-time.md` has timings a
check could be budgeted against.

**What makes this its own ticket:** the false alarm will
be forgotten by morning. The absence of any signal will not.
