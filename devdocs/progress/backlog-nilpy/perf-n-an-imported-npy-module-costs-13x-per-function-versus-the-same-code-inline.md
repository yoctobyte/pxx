---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "MECHANISM, and it is the thing to look for again: a routine that scans a WHOLE-PROGRAM array once per DEFINITION, where that array holds every imported module concatenated -- so per-definition work scales with the import closure and an inline arm never pays it. It SPRINGS wherever a new per-definition or per-lookup scan is added over Tokens or UCls; it is not tied to any routine named here. THREE instances found and fixed, all landed and carried by pin v415: PyDefSiteMode's backward walk (now a precomputed enclosing-construct table), PyDefUsedAsValue's allocating CaseEqual(GetTokenStr(j),nm) per identifier token (now non-allocating TokenCaseEqual, length reject first, 62 sites) -- those two together MEASURED 12.4% -- and FindUClass's flat class-table scan, three scans per call with no early exit on the first, 4.31 BILLION true steps on lekkerzeilen (now a name-keyed hash index preserving the ranking exactly, d5de02143). INDEX MEASURED: 38.72% on lekkerzeilen (min-of-5, pin v414 aeadb1754b80 vs 94fddf62ee6af731 = pin v415, arms sha-pinned, outputs byte-identical) and 28% on uforth (frankh-c0, 131x step reduction). It GENERALISES -- an earlier +0.0% cross-corpus null was a stale arm built before the commit existed and is retracted. The ticket's own retirement condition (an interleaved min-of-N on lekkerzeilen with load recorded) IS NOW MET. STILL OPEN AND WHY THIS IS NOT CLOSED: the structural one-pass version is available and unbuilt for the scans that remain. A FOURTH AND FIFTH INSTANCE were found 2026-09-22 and NEITHER WAS IN THE CENSUS ABOVE -- PyClsAttrWriteScan and PyDynAttrEverAssigned scan from j := 1, and that census filtered on loops starting at 0, so the blind spot was the START VALUE and not the bound spelling this ticket named. MEASURED AND DELIBERATELY NOT BUILT: PyClsAttrWriteScan is 165 calls / 47,776,271 token visits on lekkerzeilen and removing it outright is worth 4.1% of the build (min-of-3 interleaved, base 62.93 s vs off 60.35 s, with a combined-define control reporting visits=0); PyDynAttrEverAssigned is called ZERO times there. The one-line `if classW and instW then Break` is semantically exact and worth NOTHING -- identical visit count, byte-identical output -- so only the table captures the 4.1%, which does not justify ~200 lines in the routine that decides class-attribute lowering at this ticket's rank. TWO RETRACTIONS BY THE SAME HAND, both in devdocs/perf/lekkerzeilen-build-time.md: 1.1% was reported off round 1 of a 3-round sweep (per-round 0.71/3.03/2.58) and read as a null; and the explanation offered for the small number -- that lekkerzeilen's build is not parse-dominated -- is FALSE and refuted by this ticket's own 38.72% FindUClass row. The real reason is magnitude alone: 4.31e9 steps against 4.78e7, 90x fewer for 9.4x less time. THE 13x HAS NOW BEEN RE-MEASURED (2026-09-22, franks-5b) AND IT IS NOT GONE: IT IS 6.2x. Same method as the original (identical bodies inline vs moved into one imported module), min-of-3 INTERLEAVED, compiler 734d10ec7b53 at cbb8f81c0, CWD repo root, load ~4 and stable across the run: 100 fns 2.30 vs 3.25 s, 200 fns 2.50 vs 4.52 s, 400 fns 2.93 vs 7.13 s. Per function off the 100->400 span, inline 2.10 ms and imported 12.93 ms, ratio 6.2x against the original 3.4/45 ms = 13.2x; the implied fixed cost lands at 2.09 s and 1.96 s for the two arms, which is the check that the slope is real rather than a fixed-term artefact. CARRY BOTH ROWS, DO NOT SUBTRACT THEM: the 13.2x was taken in another session at an unrecorded load, so the per-function MILLISECONDS are not comparable across the two and only the within-session RATIOS are -- each arm pair was interleaved, so shared load divides out of a ratio and does not divide out of a duration. What is safe to say: the ratio more than halved and the observable survives. Method, both refuted hypotheses, the retraction, and two harness faults of opposite sign: devdocs/perf/lekkerzeilen-build-time.md."
---

# An imported `.npy` module costs ~13x per function versus the same code inline

Full measurement, method and the refuted hypotheses:
**`devdocs/perf/lekkerzeilen-build-time.md`**.

## Why this is ranked where it is

It is the dominant cost of compiling lekkerzeilen, which is a stated goal
(*"have lekkerzeilen compile under nilpy as demo"*). It is not ranked on the
count of modules that hit it — every `.npy` import hits it, so that count is a
property of the language, not evidence about the fix.

## The condition that would retire this ticket

A per-function cost for an imported module within ~2x of the inline arm, at
K=400, measured the same way. Stated as a rate rather than a wall-clock figure
deliberately: the 125 s lekkerzeilen number moves whenever the demo or the
compiler does, and a summary that cites a row which fires today acquires a
dependency on that row staying broken.

## What is NOT claimed

That the import path is doing redundant work — that is the obvious reading and
it is not measured. The output being byte-comparable is consistent with
redundancy and equally consistent with a different, slower route to the same
result. Locating it needs the profile.


## 2026-09-21 — cause found, two fixes landed, timing still open

`ffe476877` fixes both instances; `bb6c6c6d4` writes up the second.

**The question this ticket asked — "what does an import require that inlining
does not?" — has an answer, and it is not something an import *requires*.** It
is that several parser routines scan the token ARRAY, the array is shared by
every module, and an import concatenates its module into it. **Nothing about
the imported code is special; it is present, and presence is the cost.**

**Read that as the thing to grep for, not as two closed bugs.** Any routine
that scans from 0, or to `TokCount`, or to `MainProgramTokCount`, once per
definition has this shape. Two were found by reading a profile; there is no
reason to believe two is the population.

**The allocation finding is the one with reach beyond NilPy.**
`CaseEqual(GetTokenStr(idx), nm)` appears **177 times across the compiler** —
62 in `pyparser.inc` (fixed), 62 in `pasparser_prog.inc`, 35 in
`pasparser_generic.inc`, and the rest scattered. Every one of them allocates a
string to throw it away. **The Pascal frontend was not measured and no claim is
made about it**; the owner's scope for this lane is compiling Python faster, so
the other 115 sites are deliberately untouched and are a separate question for
whoever owns Pascal parse time.

**On the ceiling, and why the optimistic number must not come back.** The 9.0%
was measured with the walk disabled outright, on a synthetic whose import
closure is ONE module. Under the model that fits that data — per-definition
cost `C + K/2`, with `C` the closure's definition count and `K` the module's
own — a one-module closure is the smallest `C` there is. **So 9.0% is a ceiling
for that population and may be a floor for lekkerzeilen's.** The owner raised
this without seeing the model. It is not settled, and the arithmetic that once
allowed "~5x" is not evidence for anything.

## The 13x re-measured, 2026-09-22 — it is 6.2x and it is still there

The ticket stayed open partly because nobody had re-run the original
observable after the three fixes landed. Re-run with the ticket's own method
(`devdocs/perf/lekkerzeilen-build-time.md:119`), min-of-3, arms interleaved:

| functions | inline | imported | ratio |
| ---: | ---: | ---: | --- |
| 100 | 2.30 s | 3.25 s | 1.4x |
| 200 | 2.50 s | 4.52 s | 1.8x |
| 400 | 2.93 s | 7.13 s | **2.4x** |

    per function, off the 100->400 span:  inline 2.10 ms   imported 12.93 ms   6.2x
    implied fixed cost:                   inline 2.09 s    imported 1.96 s
    compiler 734d10ec7b53, commit cbb8f81c0, CWD repo root, load ~4, stable

**Against the original `inline ~3.4 ms / imported ~45 ms = 13.2x`.** The
observable is not gone; it more than halved.

**What may and may not be quoted from this.** The two arms here were
interleaved in one session, so shared load divides out of the **ratio** — that
comparison is sound. The original's per-function **milliseconds** were taken in
a different session at an unrecorded load, so `45 ms -> 12.93 ms` is not a
clean 3.5x and must not be stated as one. Both rows stand with their own
conditions.

**Sanity check that the slope is real:** the implied fixed cost comes out at
2.09 s and 1.96 s for the two arms independently. A fixed term that agrees
across arms is what says the per-function slope is the thing that differs,
rather than the ratio being an artefact of a large constant.

**Output check:** at 400 functions the two binaries are 2,039,100 and 2,043,324
bytes — 0.2% apart, the import bookkeeping. The original recorded 18 bytes, so
this is **not** the same near-identity and I am not claiming it; the arms build
the same program modulo the import, which is what the comparison needs.

**What would retire the remainder:** the parser scans are still O(tokens) per
definition — only each step got cheaper — so the structural one-pass version
is the open work, and this 6.2x is the number it has to beat.

## 2026-09-22 — the shape was censused and there IS a third instance

This ticket said, in its own words, *"there is no reason to believe two is the
population."* Censused rather than profiled: loops in `pyparser.inc` that
**start at 0/1 and are bounded by `TokCount`/`MainProgramTokCount`** — four
hits in three routines. Two are benign (`ParsePyProgram` runs once per program;
`PyBuildEnclTable` IS the one-pass fix). The third is **`PyDefUsedAsValue`**,
called from `PyParseDefHeader` once per definition per pass, and it only exits
early when it FINDS something, so the common answer pays the whole stream.

    arm       fns  calls  width    token visits
    inline    400  800     13,611   10.9M
    imported  400  800    250,059  200.0M      18.4x, identical call count

Fixed by the same transformation `ffe476877` applied twice: a one-pass
candidate table. Sound because the predicate is **name-independent** — every
condition is about a token's neighbours. Verified with a crosscheck against the
scan it replaces: **0 disagreements, from an instrument shown to report 368
across 55 files on a deliberately broken table**, plus the 224-test
value/Callable corpus byte-identical to `.expected` on both sides.

**Worth 1.50x on the 400-function imported arm** (interleaved min-of-3, same
tree, one define apart). The inline arms sit at 0.97-1.03x — a control that
came free, and the reason the win is attributable to the import closure rather
than to load. Full write-up, both levers left, and the numbers with their
conditions: `devdocs/perf/lekkerzeilen-build-time.md`.

**This does NOT close the ticket and the census does not retire the warning.**
The census is blind to a scan bounded by a saved copy of the count or by
`Length(Tokens)`, and it only covered `pyparser.inc`. Three found is not a
population either.

## 2026-09-22 — instances four and five, measured and NOT built

`PyClsAttrWriteScan` and `PyDynAttrEverAssigned`, both `compiler/pyparser.inc`,
both `j := 1; while j < MainProgramTokCount`, both name-parameterised with every
structural condition about a token's neighbours — the same shape as
`PyDefUsedAsValue` and convertible by the same transformation.

**The census above missed them and the reason is worth more than the instances.**
It reported "four hits in three routines" and it filtered on loops that start at
**0**. These start at **1**. The blind spot this ticket named for itself was the
bound spelling (`Length(Tokens)`, a saved copy); `Length(Tokens)` turns out not
to occur anywhere in `compiler/**` at all. **The actual blind spot was the start
value, which nobody had written down as an axis.** That is the minimal-case rule
arriving in a census: the filter fixed an axis its author never enumerated.

**Measured on lekkerzeilen, and the ceiling does not justify the fix:**

    PyClsAttrWriteScan     165 calls, 47,776,271 token visits
    PyDynAttrEverAssigned    0 calls
    removing the scan outright:  4.1%  (min-of-3 interleaved, 62.93 -> 60.35 s)
    control: both defines ->  clsattr_visits=0

`PyClsAttrWriteScan` has **no early exit by design** — it answers two questions
at once — and the obvious one-line remedy is worth nothing: `if classW and instW
then Break` is semantically exact and removes **zero** visits on this program,
because `classW` needs a write through the literal class name and that never
co-occurs with an instance write. So the 4.1% is available only via the table.

**Not built, and the reason is rank rather than difficulty.** ~200 lines in the
routine that decides class-attribute lowering, for 4.1% of a compile, at this
ticket's own prio of 60. The design is straightforward if someone wants it: a
name-keyed index over the write sites, staleness key on `MainProgramTokCount`,
overflow stand-down to the scan, `_OFF`/`_CROSSCHECK` switches — the same house
pattern as `PyBuildDValTable`. The switches to re-derive the ceiling are
committed and documented at the routine.

**Two retractions, both mine, both in `devdocs/perf/lekkerzeilen-build-time.md`.**
I reported 1.1% off round 1 of a three-round sweep and called it a null (the
per-round differences were 0.71, 3.03, 2.58). And I explained the small number by
claiming lekkerzeilen's build is not parse-dominated — **false, and refuted by
this ticket's own headline row**, where the `FindUClass` index alone is 38.72% of
that build. The explanation is magnitude and nothing else: 4.31e9 steps against
4.78e7, ninety times fewer for nine times less time.
