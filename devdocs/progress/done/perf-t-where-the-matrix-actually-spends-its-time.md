---
track: T
prio: 55
type: perf
blocked-by: []
summary: "Profile of the full tier against the owner's standing complaint that testing overhead is ~95% of development time. 70% of matrix CPU is one frontend's fixed per-invocation tax (a Track A ticket, already filed). The scheduler runs at 90% utilisation, so there is nothing to reclaim there. A per-job skip cache was measured and DECLINED at ~3% for a coverage-hole failure mode. The honest tooling-side answer is that the remaining cost is real work."
status: done
owner: pxx-aa
---

# Where the matrix actually spends its time

- **Type:** perf investigation — **Track T** (`tools/testmgr.py`, tier composition)
- **Measured:** 2026-08-26 at dev HEAD, on plexus (6 usable cores), against the
  watcher's learned metrics plus direct timing.
- **Dispatched by** the coordinator with one hard constraint: **no coverage may
  be given up.** Dropping jobs, sampling and sparser tiers were off the table by
  instruction — they buy wall-clock with truth, and matrix truth is the only
  reason `master` can advance. In scope: work repeated across jobs, artifacts
  rebuilt that could be shared, serialisation that is not required, tiers
  composed by accretion rather than measurement.
- **A measured floor was named an acceptable deliverable** up front. It is what
  this returns.

## The headline

| target | jobs | % of CPU | mean |
| --- | --- | --- | --- |
| **test-nilpy** | 719 | **70.2%** | 15.16s |
| test-core | 1450 | 15.6% | 1.87s |
| lib-test | 191 | 6.9% | 4.61s |
| test-pascal-conformance | 6 | 1.3% | 40.63s |
| everything else | 697 | ~6% | — |

**23% of the jobs are 70% of the time.** Optimising by job count optimises
`test-core` — 1,450 jobs, mean 1.87s — and wins ~15% at best. The same
inversion Track A hit from the compiler side: an aggregate that looks healthy is
not evidence about its parts.

## Finding 1 — the tax is not part of a NilPy job, it IS the job

Timed directly at HEAD, i.e. **after** the hotspot fixes that halved this
(8.62s → 4.06s):

| compile | wall |
| --- | --- |
| `begin end.` (Pascal) | 0.25s |
| `int main(void){return 0;}` (C) | 0.44s |
| zero-byte `.npy` | **4.49s** |
| `test/test_nil_python_core.npy` — a real test | **4.59s** |
| `test/lib_mimic_xml_etree_elementtree.npy` — 288 lines, the biggest | 5.58s |

A real test costs 4.59s against an empty file's 4.49s: **the test content is
free**. Narrowing it further — a *Pascal* program whose entire body is
`uses pylib;` costs **2.93s**, so ~2.7s of the tax is `pylib.pas` (18,996 lines)
alone, before `pyeval.pas` (5,733) and the frontend's own setup.

Paying that once instead of 719 times removes **~3,016 CPU-seconds** at zero
coverage cost.

**It is not fixable from the tooling side, and that is the important half.**
`-Fu` adds a unit *search root*, not a cache; there is no precompiled-unit
facility. A harness cannot share an artifact the compiler has no way to emit or
consume. Evidence appended to the owning lane's existing ticket,
[[perf-a-every-npy-compile-still-rebuilds-the-whole-nilpy-runtime]] — T owns the
tool, never the bug — where it is also flagged that `prio: 45` understates the
largest identified block of pure repeated work in the matrix.

## Finding 2 (negative) — the scheduler is fine. Do not start here.

12,319 CPU-seconds against 13,663 core-seconds available (2,277s wall × 6
cores) = **90% utilisation**. ~1,343 idle core-seconds is close to the floor for
a job graph with dependencies.

There is no serialisation to unpick and no parallelism to reclaim. Recorded
deliberately: the scheduler is the intuitive first place to look and it is the
wrong one, and a negative result nobody wrote down gets re-measured.

## Finding 3 (declined) — a per-job skip cache: ~3%, with a coverage-hole failure mode

The one genuine tooling lever. A `pin_built` job builds only with
`$(PXX_STABLE)` and its own sources, so when neither the pin nor those sources
changed since the job last ran, its verdict provably cannot have changed and
re-running it is pure repeated work. The predicate exists — `pin_observable()`,
built the same day for the blame-range work.

Measured over the 254 consecutive full-tier pairs on record:

- **10%** of pairs had *zero* pin-observable change — the coarse rule fires
  rarely, worth ~0.6% of the matrix on average.
- A finer per-source rule fires more often. Classifying the last 118 pairs by
  what changed: `test/` only 36%, nothing observable 13%, a pin move in 35%,
  `lib/` in 33%. So in roughly half the runs most of the 191 `lib-test` jobs are
  provably unchanged, worth **~3% of the matrix**.

**Declined.** Three percent buys a mechanism whose failure mode is *a job that
should have run and did not*, reported as a pass. That is precisely the defect
class this repo spent 2026-08-25/26 removing in five other guises — an
unenrolled rung asserting nothing, a torn-down run silencing the request for
coverage, unreached jobs reading as FIXED. Adding a sixth source of it to save
three percent, under an explicit no-coverage-loss constraint, is a bad trade at
any exchange rate. Revisit only if the tax in Finding 1 is fixed and 3% becomes
a large share of what remains.

## Conclusion

**~70% of matrix cost is one Track A ticket**, and the register-allocation work
(`feature-opt-o3-register-pressure`, re-prioritised 35 → 85 the same day) is
most of the rest — our own `-O2` build compiles `empty.npy` in 4.06s where the
same source built by `fpc -O2` does it in 1.06s.

**The tooling side has no waste of comparable size left in it.** The remaining
cost is real work: compiling real programs and running them. That is the
measured floor, and it means matrix wall-clock should be treated as a compiler
performance problem, not a test-infrastructure one.

## Log
- 2026-08-26 — profiled; findings filed to the owning lane; two levers measured
  and declined with reasons.
