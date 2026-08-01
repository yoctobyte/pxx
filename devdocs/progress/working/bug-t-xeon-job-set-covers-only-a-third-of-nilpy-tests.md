---
summary: "xeon's tracked job set covers only 117 of 352 .npy Makefile invocations, so `make test-nilpy` can be RED while xeon reports the full tier GREEN — observed 2026-08-01"
type: bug
track: T
prio: 55
---

# xeon's job set covers ~a third of the NilPy tests, so a red `test-nilpy` reads GREEN

- **Type:** bug (test infrastructure / coverage) — **Track T**
- **Opened:** 2026-08-01 by the A/N/P/C agent. Filed as an observation with the
  raw numbers; **not diagnosed** — the investigation belongs on the xeon box.
- **Context:** xeon's watcher has only been up since 2026-07-31, so a partial
  job set is an expected shape for a new deployment rather than a regression.

## What was observed

`b78988fe8977` was reported by xeon as GREEN on **native, full and opt**:

```
2026-08-01T11:32:00Z  b78988fe8977  tier=native  GREEN
2026-08-01T11:35:55Z  b78988fe8977  tier=full    GREEN
2026-08-01T11:40:40Z  b78988fe8977  tier=opt     GREEN
```

At that same SHA, locally:

```
make test-nilpy   ->  make: *** [Makefile:1033: test-nilpy] Error 1
```

The failure was real and mine — `b1f5b0e0b` (three commits earlier) changed
`[1,2] + "x"` from a compile error to a catchable runtime `TypeError`, which
invalidated an existing assertion that expected the compile to FAIL. Correct
change, stale assertion; fixed separately. **The point here is only that the red
was invisible to xeon.**

## The measurable gap

Cross-referencing `devdocs/progress/tstate/xeon.json`'s `jobs` map against every
`./$(COMPILER) test/*.npy` line in the Makefile:

| | count |
| --- | ---: |
| `.npy` invocations in the Makefile | 352 |
| tracked as `test-core#src:test/<file>` by xeon | **117** |
| **not tracked** | **235** |

Untracked examples: `test_nilpy_import_sqlite.npy`, `test_nilpy_sqlite_crud.npy`,
`test_nilpy_control.npy`, `test_nilpy_kwargs_by_name.npy`,
`test_nilpy_numeric_widen.npy`, `test_nilpy_optional_param.npy`.

So `test-core` reaching GREEN does not imply `make test-nilpy` is green — roughly
two thirds of that recipe is outside the job set.

### A hypothesis that was checked and is WRONG

The three expect-failure lines (`! ./$(COMPILER) … _fail.npy`) are all untracked,
which suggested the job enumerator might skip the negated form. That does not
explain it: 235 of the 352 **ordinary** lines are untracked too. Whatever the
enumeration rule is, it is not "the `!` prefix confuses it". Recorded so the
investigation does not start down that path.

## Why it matters

The offload model (`devdocs/dev/gating-and-waiting.md`) has dev tracks confirm
natively and trust T for breadth. That trade is only sound where T's coverage is
known. A GREEN full verdict currently reads as "the NilPy suite passed" and means
"the third of it in the job set passed". Either the job set should be completed,
or the verdict should name its coverage so a reader can calibrate.

## Suggested checks on the box

1. How the job set is enumerated — is it a one-time discovery snapshot (taken
   when xeon came up on 07-31) or re-derived per run? A one-time snapshot would
   also mean every test ADDED since then is invisible; this session added 11.
2. Whether `test-core` runs `make test-nilpy` as a recipe or replays
   per-file jobs it enumerated itself. If the latter, a Makefile assertion (the
   `test "$(...)" = "..."` line) may never be evaluated at all — only the
   compile.
3. Whether the same gap exists for the other suites (`test-core` is 1044 of the
   1637 jobs; the cross-target and conformance sets may be complete).

## Related

Not the same as the known "full-tier run wipes other tiers' job status and
manufactures phantom NEW-REDs" defect — nothing here was wrongly reported RED;
a real red was simply not covered. Worth confirming they are independent.
