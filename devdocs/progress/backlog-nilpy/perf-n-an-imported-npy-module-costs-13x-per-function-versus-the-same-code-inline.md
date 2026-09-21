---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "CAUSE FOUND AND TWO FIXES LANDED (ffe476877); TIMING NOT YET MEASURED ON THE REAL PROGRAM. The mechanism is GENERAL and is the thing to look for again: a NilPy parser routine that scans the token array per DEFINITION, where that array holds every imported module concatenated (224707 tokens for lekkerzeilen), so per-definition work scales with the whole import closure and an inline arm never pays it. Two instances found, both fixed: PyDefSiteMode walked back to token 0 skipping every construct's suite (now a precomputed enclosing-construct table, one forward pass with a stack); and PyDefUsedAsValue scanned the whole stream calling CaseEqual(GetTokenStr(j),nm) per identifier token, where GetTokenStr HEAP-ALLOCATES -- CaseEqual rejected on length only AFTER the string existed, so the allocator was busy with the scan's temporaries, not with the program (now a non-allocating TokenCaseEqual with the length reject first, 62 sites). NEITHER was a memo failure: both memos were measured working (3599 hits / 400 misses on both arms); the cost was what a miss paid. CORRECTNESS PROVEN ON LEKKERZEILEN, each zero with a positive control behind it -- table-vs-walk 0 disagreements against 468 with the table deliberately broken, fast-vs-slow 0 against 67, and the emitted binary BYTE-IDENTICAL to HEAD (code=12159489B procs=11594 warnings=89). All four crosscheck defines are in-tree so this is re-derivable in two builds. THE SIZE OF THE WIN IS THE OPEN QUESTION AND NO ONE MAY QUOTE 5x: an upper-bound probe with the walk removed ENTIRELY measured 9.0% -- but on a synthetic with a ONE-MODULE closure, which is the smallest possible value of the closure term, so the owner's challenge that it may not generalise to lekkerzeilen's closure is live and unanswered. A module-count sweep (flat 20.13/19.32/19.55/21.30 s at 1/2/4/8 modules) is in TENSION with that and one of the two is narrower than its sentence. WHAT WOULD RETIRE THIS ROW: an interleaved min-of-N of ffe476877 against its parent on lekkerzeilen, on a clear box, with population and load recorded. NOT DONE: the scans are still O(tokens) per definition -- only each step got cheaper -- so the structural one-pass version remains available and unbuilt. Method and both refuted hypotheses: devdocs/perf/lekkerzeilen-build-time.md."
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
