---
track: N
prio: 60
status: open
type: perf
blocked-by: []
summary: "MEASURED 2026-09-20, three sizes, back to back on one compiler: the SAME function bodies cost ~45 ms each when reached through an import and ~3.4 ms each written inline, net of the 2.40 s fixed cost -- 13x, linear in function count on both arms, producing a byte-comparable program (400 functions: code=1809866B imported vs 1809848B inline, procs 2625 vs 2624). THE COST IS NOT REFERENCE-DRIVEN: `import mod0` with NOTHING used from it costs 20.08 s against 20.35 s when a function is called, so it is incurred by compiling the module at all and no change to the importing program can avoid it. Module count is LINEAR (1/2/4/8 modules at K=400: 20.13/38.64/78.19/170.37 s, i.e. 20.13/19.32/19.55/21.30 s per module) -- there is no cross-module quadratic and the architecture scales; the per-module CONSTANT is what is wrong. This is the dominant term in the lekkerzeilen demo, which is ~35 imported modules and compiles in 125 s. MECHANISM NOT YET LOCATED -- a sampling profile of the import path is the next step and nothing here says which phase is responsible. Population: compiler 55f1ef09492bf17e (pxx 7caadced1), default -O, CWD /home/neo/frank-user, synthetic .npy generated per run, min-of-N not needed at these effect sizes. SEPARATE second finding filed in the same document, NOT this ticket: single-file compilation is near-quadratic in function count (exponent 1.90 by N=3200), flat below ~400 functions and therefore invisible at real module sizes."
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
