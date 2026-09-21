---
slug: feature-n-random-random-the-per-instance-rng-class-is-absent
title: random.Random — the per-instance RNG class — is absent, and its absence is reported as a wrong-arity call
track: N
type: feature
prio: 40
status: done
owner: ""
created: 2026-09-20
found-by: frankH
tags: [nilpy, random, rtl, diagnostic]
blocked-by: []
summary: "SUPERSEDED 2026-09-21 BY `feature-n-random-random-has-no-per-instance-rng-class-and-the-state-machinery-already-exists` (p45) -- NOT FIXED, DUPLICATED. Both were filed by the same seat a day apart with no supersedes edge either way, and both sat live in BOARD.md; reported by frankz-e5 off the TSP survey. THE FEATURE IS STILL ABSENT: `random.Random(seed)` has no per-instance RNG class. Work the p45 ticket, which carries the reachability diagnosis (plain `import random` is consumed-only, so `random` is not bound to its unit), the two name hazards, and the retire condition. WHY THIS ONE WAS RETIRED RATHER THAN THE OTHER: its summary framed the gap around a condition that no longer holds -- that the member lookup folds case, so `Random` matched the module-level `random()` and the refusal was `pyrandom_random takes fewer arguments than were given`, an ARITY message about a call the source never wrote. The fold was fixed the same day the duplicate was found; the member is now matched as spelled, so that message is no longer emitted and a reader following this ticket would hunt a diagnostic that does not exist. Correct when written. Its unique content -- the three-line repro and the case-fold-reads-as-arity CLASS -- is absorbed into the p45 ticket and into the as-spelled work respectively."
---

# random.Random is absent; the folding makes it look like an arity error

Found 2026-09-20 (frankH) censusing That Space Program under NilPy.
`tsp/smoke.py:60` is `self.rng = random.Random(seed)` and is the only wall in
that file.

Repro, three lines, and CPython prints `Random`:

```python
import random
r = random.Random(7)
print(type(r).__name__)
```

pxx: `pascal26:2: error: Nil Python: pyrandom_random takes fewer arguments than
were given`.

A per-instance generator is what a program uses when it wants a REPRODUCIBLE
stream that other code cannot disturb — a seeded simulation, a test fixture, a
procedural world — which is precisely why `smoke.py` asks for one. Mapping it
onto the global generator would be the wrong answer rather than a partial one:
every other user of `random.*` in the process would perturb the stream, so a
seeded run would stop being reproducible and nothing would say so.

## Log
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6c9ab5d91.
