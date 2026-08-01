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

---

## FIXED — `c14bb8fc8` (claude@xeon, 2026-08-01)

Your observation was right; the cause was simpler than any of the hypotheses.

**`test-nilpy` was in no tier at all.** `TIERS` lists `test-smoke`, `test-core`,
`test-threads`, `test-asm`, `test-debug-g`, `lib-fpc-clean`, the conformance and
cross-target sets — and never `test-nilpy`. `grep -c "test-nilpy"
tools/testmgr.py` returned **0**. The 71 `.npy` files that *were* covered are
ones appearing in other targets.

Measured against testmgr's own generator rather than the display output (which
truncates secondary sources with `+N` and would have understated coverage):

| | count |
|---|---:|
| distinct `.npy` in the Makefile | 309 |
| appearing in **any** job's recipe | 71 |
| in no job at all | **238** |

### Your three checks, answered

1. **Snapshot or re-derived?** Re-derived every run — `generate()` calls
   `make_dry_run(tgt)` per target per run. Tests added since 07-31 are *not*
   invisible for that reason.
2. **Does `test-core` run `make test-nilpy`, or replay per-file jobs?** Neither,
   for NilPy: it replays per-file lines from the targets in `TIERS`, and
   `test-nilpy` was not one of them. Where a target *is* enrolled the Makefile
   assertion lines are replayed too — the `test "$(...)" = "..."` line is part of
   the job's recipe, which is exactly how both failures below were caught.
3. **Other suites?** `lib-test` and `demos` are also unenrolled — already filed
   as [[task-t-enroll-libtest-demos-watcher]]. The cross-target and conformance
   sets are complete.

I also ruled out my own first guess — that jobs bundle several sources, so
coverage only *looked* partial because a selector names one file. Real, but it
does not explain this: the 238 are genuinely absent from every recipe.

### After enrolling

`308/309` covered, **300 new jobs**. The straggler is `test/lib_pyexec.npy`,
which belongs to `lib-test` (ticket above). Enrolled at **native** on purpose:
that is the tier dev boxes gate pushes on, so a NilPy break now returns inside
the ~100 s fast verdict rather than waiting for a full.

### What the first run of the 300 found

Two failures, **both test-side, neither a compiler regression** — filed into
Track N, not fixed under T:

- [[bug-n-nilpy-import-sqlite-asserts-host-sqlite-version]] — asserts `3045001`
  (SQLite 3.45.1). xeon has 3.46.1 and correctly returns `3046001`. This is why
  `make test-nilpy` was red here at all: it dies on the second recipe line,
  before the other ~860.
- [[bug-n-nilpy-missing-dunder-expect-fail-assertion-is-stale]] — expects a
  *compile* error; the missing-dunder case now raises a runtime `TypeError`
  like CPython. Second instance of the pattern you already fixed once.

Expect the watcher to report these two as RED until Track N fixes them. That is
the enrollment working, not a new break.

### On your framing

> Either the job set should be completed, or the verdict should name its
> coverage so a reader can calibrate.

Completed. The second option is still worth having — nothing currently stops
another suite being added to the Makefile and silently never enrolled, which is
precisely how this one hid. A coverage line in the report would make the next
occurrence self-announcing; not done here.

## Log
- 2026-08-01 — resolved, commit c14bb8fc8.
