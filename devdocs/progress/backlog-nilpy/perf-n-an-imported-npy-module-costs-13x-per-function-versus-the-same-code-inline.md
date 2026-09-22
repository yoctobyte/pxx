---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "MECHANISM, and it is the thing to look for again: a routine that scans a WHOLE-PROGRAM array once per DEFINITION, where that array holds every imported module concatenated -- so per-definition work scales with the import closure and an inline arm never pays it. It SPRINGS wherever a new per-definition or per-lookup scan is added over Tokens or UCls; it is not tied to any routine named here. THREE instances found and fixed, all landed and carried by pin v415: PyDefSiteMode's backward walk (now a precomputed enclosing-construct table), PyDefUsedAsValue's allocating CaseEqual(GetTokenStr(j),nm) per identifier token (now non-allocating TokenCaseEqual, length reject first, 62 sites) -- those two together MEASURED 12.4% -- and FindUClass's flat class-table scan, three scans per call with no early exit on the first, 4.31 BILLION true steps on lekkerzeilen (now a name-keyed hash index preserving the ranking exactly, d5de02143). INDEX MEASURED: 38.72% on lekkerzeilen (min-of-5, pin v414 aeadb1754b80 vs 94fddf62ee6af731 = pin v415, arms sha-pinned, outputs byte-identical) and 28% on uforth (frankh-c0, 131x step reduction). It GENERALISES -- an earlier +0.0% cross-corpus null was a stale arm built before the commit existed and is retracted. The ticket's own retirement condition (an interleaved min-of-N on lekkerzeilen with load recorded) IS NOW MET. STILL OPEN AND WHY THIS IS NOT CLOSED: the parser scans remain O(tokens) per definition -- only each step got cheaper -- so the structural one-pass version is available and unbuilt; and the structural one-pass version is available and unbuilt. THE 13x HAS NOW BEEN RE-MEASURED (2026-09-22, franks-5b) AND IT IS NOT GONE: IT IS 6.2x. Same method as the original (identical bodies inline vs moved into one imported module), min-of-3 INTERLEAVED, compiler 734d10ec7b53 at cbb8f81c0, CWD repo root, load ~4 and stable across the run: 100 fns 2.30 vs 3.25 s, 200 fns 2.50 vs 4.52 s, 400 fns 2.93 vs 7.13 s. Per function off the 100->400 span, inline 2.10 ms and imported 12.93 ms, ratio 6.2x against the original 3.4/45 ms = 13.2x; the implied fixed cost lands at 2.09 s and 1.96 s for the two arms, which is the check that the slope is real rather than a fixed-term artefact. CARRY BOTH ROWS, DO NOT SUBTRACT THEM: the 13.2x was taken in another session at an unrecorded load, so the per-function MILLISECONDS are not comparable across the two and only the within-session RATIOS are -- each arm pair was interleaved, so shared load divides out of a ratio and does not divide out of a duration. What is safe to say: the ratio more than halved and the observable survives. Method, both refuted hypotheses, the retraction, and two harness faults of opposite sign: devdocs/perf/lekkerzeilen-build-time.md."
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
