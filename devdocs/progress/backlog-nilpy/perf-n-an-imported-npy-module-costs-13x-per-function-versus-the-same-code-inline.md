---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "MECHANISM, and it is the thing to look for again: a routine that scans a WHOLE-PROGRAM array once per DEFINITION, where that array holds every imported module concatenated -- so per-definition work scales with the import closure and an inline arm never pays it. It SPRINGS wherever a new per-definition or per-lookup scan is added over Tokens or UCls; it is not tied to any routine named here. THREE instances found and fixed, all landed and carried by pin v415: PyDefSiteMode's backward walk (now a precomputed enclosing-construct table), PyDefUsedAsValue's allocating CaseEqual(GetTokenStr(j),nm) per identifier token (now non-allocating TokenCaseEqual, length reject first, 62 sites) -- those two together MEASURED 12.4% -- and FindUClass's flat class-table scan, three scans per call with no early exit on the first, 4.31 BILLION true steps on lekkerzeilen (now a name-keyed hash index preserving the ranking exactly, d5de02143). INDEX MEASURED: 38.72% on lekkerzeilen (min-of-5, pin v414 aeadb1754b80 vs 94fddf62ee6af731 = pin v415, arms sha-pinned, outputs byte-identical) and 28% on uforth (frankh-c0, 131x step reduction). It GENERALISES -- an earlier +0.0% cross-corpus null was a stale arm built before the commit existed and is retracted. The ticket's own retirement condition (an interleaved min-of-N on lekkerzeilen with load recorded) IS NOW MET. STILL OPEN AND WHY THIS IS NOT CLOSED: the parser scans remain O(tokens) per definition -- only each step got cheaper -- so the structural one-pass version is available and unbuilt; and the original 13x per-function observable has NOT been re-measured since the fixes, so nobody may say it is gone. Method, both refuted hypotheses, the retraction, and two harness faults of opposite sign: devdocs/perf/lekkerzeilen-build-time.md."
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
