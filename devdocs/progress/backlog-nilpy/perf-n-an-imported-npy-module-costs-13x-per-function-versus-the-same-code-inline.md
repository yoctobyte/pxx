---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "MEASURED 2026-09-20 and PROFILED. The SAME function bodies cost ~45 ms each through an import and ~3.4 ms inline, net of a 2.40 s fixed cost -- 13x, linear in function count, producing a byte-comparable program (400 defs: code=1809866B/procs=2625 imported vs 1809848B/2624 inline). NOT REFERENCE-DRIVEN: an import with NOTHING used from it costs 20.08 s against 20.35 s when a function is called, so no change to the importing program avoids it. Module count is LINEAR (20.13/19.32/19.55/21.30 s per module at 1/2/4/8) -- no cross-module quadratic; the per-module CONSTANT is wrong. It is the DECLARATIONS not the bodies: emptying every body to `pass` saves only 2.3 s of 20.1. THE PROFILE REFUTED declaration-registration (pre-registered criteria; registration is ~0%) and the two arms differ in SHAPE: imported collapses onto GetTokenStrFromRaw 16%, PyFindSuiteIndent 13%, PXXAlloc 11%, PXXFree 10% across 20 symbols, while the identical code inline is diffuse over 46 symbols with nothing above 11% and PyFindSuiteIndent ABSENT. In absolute time that is ~30x more token-string extraction for the same tokens. PyFindSuiteIndent (pyparser.inc:39422) is a deliberately BOUNDED scan, so 2.76 s in it means the CALL COUNT is the defect, not the walk. THE OPEN QUESTION IS NOW SHARP: the inline arm compiles the identical 400 definitions, so what does an import require that inlining does not? A site/inference pass is the fitting explanation and is NOT established -- flat self-time has no caller information, so confirm call counts before acting on it. Reproduces on two compilers (5.4x on 55f1ef09492bf17e, 5.6x on 2d692164aea6). Full method: devdocs/perf/lekkerzeilen-build-time.md."
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
