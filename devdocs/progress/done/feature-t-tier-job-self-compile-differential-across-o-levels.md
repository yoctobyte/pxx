---
track: T
prio: 50
type: feature
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19: a Track T tier job that compiles compiler.pas at every -O level and DIFFS the results across levels. Not in the per-fix loop — quick-gating must not slow down. The point is optimizer differential coverage as Track O ramps up, NOT the code-size issue that surfaced it; compiler.pas is the largest, densest program we can run the optimizer over."
status: done
---

# Tier job: self-compile differential across `-O` levels

**Implements [[decide-should-the-gate-prove-self-compile-at-more-than-one-o-level]]**
(user, 2026-08-19). Filed as work because a decided ticket that is never re-filed is
invisible to `ready`/`next`.

## What to build

A Track T tier job that compiles `compiler/compiler.pas` at **every** `-O` level and
**compares the results across levels**.

**Not in the per-fix loop.** The user was explicit that this must not hinder quick-gating.
The dev loop stays `make compiler/pascal26` + repro + `tools/gate.sh quick`.

## Build it as a DIFFERENTIAL, not as a smoke test

The framing matters more than the mechanism. "Does `-O0` still compile" is the weak
version, and its motivation is already spent: the failure that prompted this was
`MAX_CODE`, a **runaway guard** rather than a real constraint, now 8 MB to 16 MB with the
default build at 44%. Size will not catch anything again soon.

**The lasting value is optimizer coverage.** If the compiler built at `-O0` and at `-O3`
disagree about *anything*, that is an optimizer bug — and `compiler.pas` is the largest,
most edge-case-dense program available to run the optimizer over. **This grows in value as
Track O ramps up** (new `-O3` passes, per-pass promotion to `-O2`); it is the cheapest
optimizer-differential the project owns.

## Most of it exists already

The bench harness already emits `CANARY-DIFF vs -O0` for the `-O2` and `-O3`
`selfcompile` rows — a cross-level comparison, and the thing that surfaced the original
failure. **Formalise and extend that into a tier job rather than building a second
mechanism.** T owns tier composition and should size it.

One behaviour to preserve from that incident: when the `-O0` build failed, `-O2` and `-O3`
reported `CANARY-DIFF vs -O0` purely because the baseline did not exist — **three red rows,
one defect.** The job should distinguish "baseline missing" from "levels genuinely
disagree", or every future failure reads as three.

## Known and counter-intuitive

**Lower `-O` levels emit MORE code**, so a build that fits at `-O2` can overflow at `-O0`.
The error text names this now; the job's reporting should not assume the opposite.

## Gate

Track T's own tooling gate, and test the tooling with QUICK tiers plus a scratch bare repo
rather than long runs.

---

## RESOLUTION 2026-08-26 — built, measured, enrolled in `full`

### The property held, and this is the first time anyone checked it

```
BUILD -O0 ok  22s  10,456,651 bytes
BUILD -O1 ok  22s   9,419,028 bytes
BUILD -O2 ok  23s   9,374,089 bytes
BUILD -O3 ok  29s   9,317,366 bytes
same -O1/-O2/-O3 vs -O0  compiler/compiler.pas
same -O1/-O2/-O3 vs -O0  test_ansistring / test_class_of /
                         test_dynarray_torture / test_cross_exception
odiff: GREEN — every level that built emits identical bytes
```

Note the sizes: **-O0 emits 1.14 MB more than -O3**, confirming the ticket's
warning that lower levels emit *more* code and that -O0 is where a size ceiling
bites first. Nothing in the reporting assumes otherwise.

### Cost, and the tier call

**~200s wall**, measured on this box while the watcher was running: ~96s for the
four builds, ~104s for the differential (each stage compiling `compiler.pas`,
plus four dense test programs).

Enrolled in **`full`, not `native`**:

| tier | wall | what 200s costs it |
| --- | --- | --- |
| native | ~350s, ~2,100 core-sec | **~10%** for one job |
| full | ~2,300s, ~12,300 cpu-sec | **1.6%** |

The alternative — thinning what it asserts so it fits a faster tier — was
rejected. A weak differential that runs often is worse than a strong one that
runs rarely, because the weak one *also* discharges the urge to look. It is
`pin_built: False` and appears in **no** other tier, so quick/native/limited
keep the pin-free property that lets a pin be taken during a native window.

### It asserts the strong thing, not the weak one

Not *"does -O0 still build"* — that motivation is spent (`MAX_CODE` was a
runaway guard, since raised 8 MB → 16 MB, default build at 44%). It asserts
**a compiler built at -O0 and one built at -O3 must emit the same bytes.**
Optimising the compiler may change how fast it runs; it must not change what it
produces. `compiler.pas` is the densest input available, and it is used as an
input as well as the thing being built.

This closes the hole CLAUDE.md names in its own claims section — the self-host
fixedpoint proves reproducibility **at one optimisation level**, and the
2026-08-19 `-O0`-only failure passed the entire gate and was found by a
benchmark, i.e. by luck, in a phase that only runs when the box is idle.

### The three-rows-one-defect bug is fixed in both places

The bench harness's version reported `CANARY-DIFF vs -O0` for every level when
the `-O0` **build** failed — against a baseline that was never produced. One
defect, three red rows, and no way to tell *the levels disagree* from *there was
nothing to compare against*. **A diff against a missing operand.**

Four states are now named apart, in the new script and in
`testmgr.py`'s bench loop:

- `BUILD-FAIL` — this level's compiler did not build
- `NO-BASELINE` — the baseline emitted nothing; this level was **not** compared
- `EMIT-FAIL` — this level's compiler could not compile the input
- `DIFF` — the levels genuinely disagree; **the only optimizer finding**

And a failed `-O0` no longer discards the rest: the baseline falls back to the
first level that *did* build, announced explicitly, because "do -O1/-O2/-O3
agree" is a real signal that survives -O0 being broken.

### Classing

`selfhost` (600s timeout). It classes that way today because `make -n` expands
the `$(COMPILER)` prerequisite and *that* text names `compiler.pas` — an
accident of the prerequisite rather than anything about the script — so
`classify()` now matches `selfcompile` directly as well. A `unit` class would
have killed 200s of legitimate work at 90s and published it as a red, which is
the uforth false-red again.

### Files

`tools/selfcompile_odiff.sh` (new, T), `tools/selfcompile_odiff_devtest.py`
(15 cases, driving all four states with fake compilers — on a healthy tree only
one branch ever runs), `testmgr.py` (classify + the bench baseline fix + tier
enrolment), and **two lines of `Makefile`** — Track A's file-lane, kept to the
enrolment point with the logic in T's lane.

## Log
- 2026-08-26 — built, run green, sized, enrolled in `full`.
- 2026-08-26 — resolved, commit ab8d17d20.
