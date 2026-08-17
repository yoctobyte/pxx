---
track: T
prio: 45
type: feature
status: done
---

# Track T: uforth benchmark harness — pxx-compiled vs interpreted Python baselines

## Idea (user-requested)

uforth is a real, non-trivial NilPy program with a large deterministic
workload (the Forth-2012 suite + microbenches), which makes it the natural
speed oracle for the NilPy backend: the SAME uforth.py runs

1. **plain interpreted Python** — `python3 uforth.py` (the CPython
   interpreter running the source),
2. **CPython** baseline variants as useful (e.g. `python3 -O`, and a PyPy
   column if installed — cheap to add, big JIT reference point),
3. **pxx** — `pascal26 uforth.py` compiled native.

Same stdin scripts, wall-clock + max-RSS per runtime, speedup table.

## Workloads

- The suite drivers already used for conformance (prelim, core.fr,
  localstest, filetest, …) — real mixed workload.
- The DO/LOOP shift/and/xor microbench from the promoint fast-path work
  (10k iterations) — pure interpreter-dispatch hot loop.
- blocktest's ELF-HASH section — the known ~100x-slow outlier; a tracked
  number keeps the regression visible and measures future Track O wins.

Current known figure for context: pxx-compiled uforth ≈ 9x slower than
CPython on prelim (2026-07-21); fast paths took the DO/LOOP microbench
from 31s to 7.5s.

## Ownership / shape

Track T owns the TOOL (a `tools/` bench script or a testmgr bench tier —
T's call; the borg already has a `bench` job shape to hang rows on).
Findings are NOT fixed under T: a slow path goes to Track O (implicitly A)
or N as a ticket, per "T owns the tool, never the bug". Needs uforth
checked out (path configurable, default ~/projects/uforth); skip cleanly
when absent or when python3/pypy is missing. Keep runs bounded — a
--quick mode without ELF-HASH for routine runs, the full set for nightly.

## LANDED 2026-07-22 — tools/uforth_bench.py (f783cd25)

Standalone harness (T's call over a testmgr tier: the cross-runtime shape does
not fit the pxx-vs-FPC bench face). `make bench-uforth` [`BENCH_FULL=1`].

- **Runtimes:** cpython, cpython-O, pypy-if-present, pxx-native.
- **Workloads:** microbench-doloop, prelim (prelimtest.fth), core
  (tester.fr+core.fr concatenated — the suite pieces THROW -13 without the
  TESTING preamble), blocktest-elfhash (full only).
- **Source = GitHub** (git@github.com:yoctobyte/uforth): fetches origin, warns
  when the checkout is behind, and stamps the uforth sha into every bench.tsv
  row (7th column) so a number is tied to a specific source.
- **Quality:** min wall over N clean runs, descheduled runs discarded
  (wall>cpu*1.4); max-RSS from the child rusage via wait4. Skips cleanly when
  uforth/python3/a usable pxx is absent; a workload the base runtime can't run
  is SKIPped with a reason, not emitted as partial rows.
- **Must use the CURRENT compiler** — pinned stable can't lex uforth's
  char-code literals (`empty char-code literal after #`); default --pxx is the
  repo compiler, `make bench-uforth` passes ./$(COMPILER).

### First numbers (noisy — box under concurrent full-tier load)
| workload | cpython | pxx | speedup | pxx RSS |
| --- | --- | --- | --- | --- |
| microbench-doloop | ~5.6s | ~17.8s | 0.31x (3.2x slower) | 582 MB |
| prelim | ~0.43s | ~1.77s | 0.24x | 32 MB |
| core | ~0.89s | ~5.1s | 0.17x | 166 MB |

pxx is 3-6x slower and 5-24x the RSS on these — **Track O findings, filed
there, not fixed under T**. The 582 MB microbench RSS is the standout (the pxx
runtime/GC footprint on a tight loop). Consistent with the ticket's prior
"≈9x slower on prelim" ballpark; fast paths already took DO/LOOP 31s→7.5s.

### Follow-ups (filed, not blocking)
1. **ELF-HASH workload** — blocktest.fth needs uforth's block-word preamble
   (FIRST-TEST-BLOCK / LIMIT-TEST-BLOCK / `[?IF]`) that tester.fr alone does not
   provide, so blocktest-elfhash currently SKIPs. Assemble that preamble, or
   extract the ELF-HASH section as a standalone snippet, to restore the tracked
   ~100x outlier.
2. **Daemon idle-bench integration** — the harness is standalone + a make
   target today. Hanging it off the watcher's idle `bench` phase (so uforth
   rows land per-sha automatically) is a separate step; the row schema already
   matches bench.tsv.
3. **Run on a quiet box** for a clean baseline — the numbers above were taken
   while the full-tier daemon was running; re-baseline when idle.

## Reading the numbers (user, 2026-07-22) — these are GOOD, not a slowness flag

The pxx-vs-CPython ratios must NOT be read as "pxx is slow". uforth is a Forth
VM built on heavy dynamic dispatch — `exec()` (uforth.py:1289), ~17
exec/eval/getattr sites, PYTHON-bodied words compiled and run dynamically. That
is close to the worst case for an AOT compiler and close to the best case for
CPython, whose decades-tuned C eval loop (and, on newer builds, its JIT) is
exactly built to chew through this shape.

**And it is heavier than uforth.py alone suggests (user, 2026-07-22):** the
.UFO stdlib is itself full of dynamic bodies — **141 PYTHON-bodied words across
all 10 .UFO files** (1964 lines), compiled and `exec`'d on EVERY run during
startup, before the workload begins. So a short workload like prelim (279 ms)
is largely stdlib-load time dominated by exec'd Python bodies. The dynamic
surface pxx must route through its Python-body path is far larger than the
uforth.py `exec()` sites alone — which makes staying within ~6x of CPython on
these runs a stronger result still.

So on that terrain:
- **core 0.16x / prelim 0.17x** — within ~6x of CPython on a dynamic-dispatch-
  heavy REAL program is a strong result, not a gap to close.
- **microbench-doloop 0.43x** — on the tight interpreter loop, within ~2.3x of
  CPython. Very good; this is the path the promoint fast-paths already target
  (they took it 31s→7.5s earlier).

The one real follow-up is **memory**, not speed: pxx peak RSS is 582 MB on the
microbench vs CPython's 24 MB (~24x). That is the pxx runtime/GC footprint on a
tight loop and the thing worth looking into later — filed as [[bug-a-runtime-variant-heap-grows-unbounded]] (the memory
item), NOT as a speed regression.

**Claims discipline for any public copy:** if these ever appear in
docs/website, frame them honestly — "competitive with CPython on a
dispatch-heavy Forth VM" is fair; "as fast as CPython" is not (it is 0.16-0.43x
here), and the numbers are workload-specific. State the workload and that pxx
AOT-compiles a program whose hot path is dynamic dispatch.

## 2026-08-13 — triage: the DATA exists, the HARNESS does not

Worth recording before this ticket is picked up, because the bench series makes
it look done. `tstate/bench.tsv` carries 45 rows across three of this ticket's
workloads:

```
uforth-prelim            15 rows
uforth-microbench-doloop 15 rows
uforth-core              15 rows   (levels: pxx, cpython, cpython-O)
```

All 45 are dated **2026-07-23**, all from host **borg**, and there have been
none since — borg is the dev station now and Track T moved to plexus.

`grep -rn 'uforth-prelim' tools/` finds nothing, and `git log -S` finds it in no
commit that ever touched `tools/`. So the numbers were produced by something run
outside this repo (the uforth project dir), not by a harness anyone can re-run.
That is the actual gap: the ticket is not "build a benchmark", it is **land the
thing that made those rows, so a second run is possible** — one host, one day,
unreproducible is the same as no baseline.

Anyone picking this up: the 45 rows are still a useful sanity check on the
harness's output shape, but do not treat them as a comparable baseline. They
predate the 2026-08-02 MEASUREMENT BASIS CHANGED line at the top of bench.tsv,
which explicitly says not to compare across it.

## 2026-08-17 — verified working, follow-ups actually filed, resolving

The harness landed 2026-07-22 and the ticket then sat in the ready queue for
almost a month. Two things closed it out.

### The three "filed, not blocking" follow-ups were NOT filed

Checked before resolving, and none of the three existed as a ticket anywhere —
the exact invisible-work class
`project_decided_tickets_are_invisible_work_and_get_rediscovered` describes, and
the same way `bug-t-twatch-status-false-down` sat unbuilt after being named only
in a `decided/` body. Now real, rankable tickets:

- [[feature-t-uforth-bench-on-the-watcher-idle-phase]] — daemon integration.
  **This subsumes follow-up 3** ("run on a quiet box"): the watcher's idle bench
  phase already refuses to bench under load, so hanging uforth off it makes the
  quiet baseline a property of the schedule rather than of someone catching the
  box idle by hand. It is also the instrument for the open slow-creep residual
  in [[bug-t-a-timeout-bisects-to-an-innocent-commit]].
- [[feature-t-uforth-bench-restore-the-elfhash-outlier]] — the skipped ~100x
  workload.

### Re-run confirms the harness works, and the numbers have moved a lot

`--runs 1 --no-write`, on a box with a co-tenant (so read the ratios loosely —
the RSS figure is not loose):

| workload | cpython | pxx | speedup | pxx RSS | was (2026-07-22) |
| --- | --- | --- | --- | --- | --- |
| microbench-doloop | 17.7 s | 29.6 s | **0.60x** | **16.7 MB** | 0.31x, **582 MB** |
| prelim | 0.52 s | 1.29 s | **0.40x** | 16.7 MB | 0.24x, 32 MB |
| core | 1.44 s | 3.97 s | **0.36x** | 16.7 MB | 0.17x, 166 MB |

Speedups roughly doubled across all three. **The standout is RSS: 582 MB → 16.7
MB on the microbench**, a ~35x reduction, and now flat at 16.7 MB across
workloads rather than scaling with the run. That was the single worst number in
this ticket ("the pxx runtime/GC footprint on a tight loop") and it is gone.

Both runs were taken under co-tenancy, so the wall-clock ratios carry the usual
caveat and a ~2x swing is available from load alone — but a 35x RSS change is
far outside that, and flat-across-workloads is a structural signature rather
than a noisy one. Whatever landed, it worked; attributing it is Track O/N's, not
T's.

**T owns the tool, never the bug** — no finding here is fixed under T, and the
remaining ratios stay Track O's to read against this ticket's own guidance that
they must not be read as "pxx is slow" (uforth is a Forth VM on heavy dynamic
dispatch, near the worst case for AOT and the best for CPython, with 141
PYTHON-bodied stdlib words exec'd at every startup).

Resolving: the deliverable landed, it demonstrably runs, and the follow-ups are
now rankable work rather than prose.

## Log
- 2026-08-17 — resolved, commit def4bce85.

### Attributed 2026-08-17 — the RSS drop is the in-place append fix

Verified independently (shas, dates, subjects, and the pin diff all check out):

| commit | date | what |
| --- | --- | --- |
| `9ffbba0bd` | 2026-08-14 | `perf(A): append in place for s := s + x — Pascal accumulation goes linear` |
| `e0d7b6ca7` | 2026-08-14 | `perf(A): append in place on VARIANT slots too — this is NilPy's actual shape` |
| `600b676a1` | 2026-08-14 | `docs(O): re-profile — concat 62.5% -> 6.79%, rest is alloc churn` |

`s := s + x` in a loop was quadratic: each iteration allocated a fresh buffer
and copied. That predicts **both** observations, and the second one is the tell:

- RSS scaling with run length — the dead buffers accumulate;
- RSS going **flat at 16.7 MB across all three workloads** once the append
  happens in place. A GC-pressure story would have scaled everything down
  proportionally, leaving three different numbers. Flatness is structural, which
  is why it survives the co-tenancy caveat that the wall ratios do not.

**And the first fix alone did nothing for NilPy.** It needed `e0d7b6ca7`,
because NilPy's loop-carried string is a **Variant** slot rather than
`tyAnsiString` — the typed arm was fixed while the shape NilPy actually emits
stayed quadratic. Two stores, one concept, and the obvious one was not the
load-bearing one. Same shape as
[[bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name]]'s eight soft
intrinsics: fixing the reported site is not the same as fixing the concept.

**One correction to the attribution as offered:** it noted the pin moved (v299,
`86da0606d`) "so a `PXX_STABLE`-built benchmark sees them". True, and **not why
this benchmark saw them** — `uforth_bench.py` defaults `--pxx` to
`compiler/pascal26` and `make bench-uforth` passes `./$(COMPILER)`, both HEAD-built,
because the pinned stable cannot lex uforth's char-code literals (recorded above).
This harness never reads the pin. It picked the fix up on 2026-08-14 because the
commits were in HEAD, pin or no pin. The attribution is unaffected; the mechanism
is a true fact about a different benchmark.

**The residual 0.60x is already characterised**, not an open question:
`600b676a1` re-profiled immediately after and recorded concat down to 6.79% with
the rest being **alloc churn**. That makes
[[feature-t-uforth-bench-on-the-watcher-idle-phase]] the right next instrument —
churn wants an undisturbed series, not one quiet run.

### 2026-08-17 — the "pin cannot lex uforth" reason is STALE, and the hazard got worse

This ticket records, as the reason the harness defaults to the HEAD compiler:

> *Must use the CURRENT compiler — pinned stable can't lex uforth's char-code
> literals (`empty char-code literal after #`)*

**No longer true.** Measured today: pin v344 compiles `uforth.py` fine and
produces a full pxx column. The limitation was real when written and has since
been fixed.

That is worth more than a documentation tidy, because the hazard it described
has been replaced by a **worse** one. A pin that cannot compile fails cleanly
and announces itself. A pin that *can* compile produces a full, plausible pxx
column for a compiler that is **not the one any recorded figure was taken
with** — and says nothing.

**RETRACTED, same day:** this section first cited "HEAD 29.6 s vs pin 44.1 s" as
evidence the pin was stale. That attribution was wrong, and the correction is
worth more than the claim was:

- pin **v344** (`da44f561e`, 2026-08-16) **postdates** v299 (`86da0606d`,
  2026-08-14), the pin that carried the in-place append work — and contains
  both `9ffbba0bd` and `e0d7b6ca7`. Verified by `merge-base --is-ancestor`.
- the two binaries are ~77 bytes apart.

Two compilers 77 bytes apart, both carrying the same perf work, cannot differ by
1.49x. And 1.49x sits inside the **1.96x** co-tenancy range measured on this
very box (403 s → 791 s), on a day it was running three dev sessions plus
sweeps. So the figure almost certainly measured **contention**, not the pin.

Settling it needs two interleaved builds on a quiet box, which nobody has had
lately. Until then the number is withdrawn rather than repaired.

**The guard stands without it.** Benchmarking with `$(PXX_STABLE)` genuinely
does measure a different compiler from every figure on record, and silence about
that is the hazard; the shipped warning says exactly that and never quantified
it. Whether the pin is faster or slower is the thing a reader should go and
measure, not be told.

**Guarded mechanically rather than by note**: `uforth_bench.py` warns when
`--pxx` is a pinned/stable path, **at selection time rather than on failure**,
saying the numbers describe the pin and that failing to reproduce the record
this way is not a regression. Warning on failure would have been useless here
precisely because there is no longer a failure to hang it on.

The stale reason is left in the text above rather than edited out, with this
section as its correction — the original sentence explains why the default was
chosen, and that history is why the default is still right.
