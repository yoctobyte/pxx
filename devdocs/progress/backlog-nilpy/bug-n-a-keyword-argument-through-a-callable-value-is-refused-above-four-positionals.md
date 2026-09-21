---
slug: bug-n-a-keyword-argument-through-a-callable-value-is-refused-above-four-positionals
title: a keyword argument through a callable value is refused above four positionals
summary: "`pascal26:531: error: Nil Python: a keyword argument through a callable value needs pyvar_callv_kw (pyeval) and at most 4 positional arguments` — TSP row 8, and it REPRODUCES at pin v414 (aeadb1754b80b622) AND at HEAD, so it is not fixed by events. SITE: `tsp/departure.py:530-531`, `dv, _, miss = aim(model, t_end, nbody.to_bary(tuple(fl.state), fl.t_us), t_arrive, target, tol=1000.0)` — five positional and one keyword. CONFIRMED BY ELIMINATION, not by the line number: six modules in `tsp/` have a line 531 and only this one matches the diagnostic's shape (>4 positional AND a keyword); `ascent.py:531` is an arithmetic assignment and `__main__.py:531` has a keyword but ONE positional. **AND THE OBVIOUS TEST IS INVALID — COMPILING `departure.py` DIRECTLY IS CLEAN, rc=0, ON BOTH COMPILERS.** The row fires only when the module is reached through `tsp/historic.py:26`'s `from . import anchor, ascent, departure, ...`. So `pxx tsp/departure.py` answers NO to a defect that is there, and a seat checking the fix that way will believe it landed. Reach it through `historic.py`. MECHANISM CANDIDATE, UNTESTED: `aim` enters by a FUNCTION-LOCAL relative import, `from .anchor import aim` at `departure.py:519`; through `historic.py` the `anchor` module is already bound at module level, and the diagnostic turns on the callee being a VALUE rather than a known function, so the entry point plausibly decides which of the two `aim` is. Recorded as a candidate because nothing here tested it. NEAR-DUP CHECKED, NOT MERGED, AND THE DISTINCTION IS THE ARITY: `bug-n-a-keyword-argument-through-a-callable-field-is-refused` is the RUNTIME refusal of a keyword through a callable FIELD (`o.zap(1, mode=2)`, ONE positional), where the field-dispatch arm falls to `pyvar_callv0..4` which take positions and have no names. THIS ticket is a COMPILE-TIME refusal where `pyvar_callv_kw` is exactly what the diagnostic asks for and the blocker is the >4 POSITIONAL cap. Same family -- the `pyvar_callv0..4` arity ceiling is visible in both -- and plausibly one root, which is why they are linked here rather than merged: the observables, the phase and the repro all differ, and closing one must not be read as closing the other. If a fix raises the callv arity ceiling, check both. PROVENANCE: filed by frankz-e5's survey as `historic.py:531`, which was the no-filename trap — an error inside an imported module prints that module's line with NO file name, so the reader supplies the file they invoked; corrected to `departure.py` by e5 and frankuser on construct+arity+import-edge agreement, and the compile that was asked for as confirmation instead produced the entry-point asymmetry above."
track: N
type: bug
prio: 55
status: backlog
owner: ""
blocked-by: []
created: 2026-09-21
found-by: frankz-e5
---

# A keyword argument through a callable value, above four positionals

## Reproduce — and note WHICH file you must invoke

    cd /home/neo/tuxspaceprogram
    pascal26 tsp/historic.py /tmp/h     # rc=1, error at 531
    pascal26 tsp/departure.py /tmp/d    # rc=0, CLEAN

Measured 2026-09-21 on **both** pin v414 (`aeadb1754b80b622`) and HEAD
(`5c8c3b8a4c051337`). Identical on both — **not fixed by events.**

**The second line is the point of this section.** The defect is in
`departure.py` and compiling `departure.py` does not show it. Anyone verifying
a future fix by compiling the file that contains the bad line will get a false
green.

## Locating it, since the diagnostic does not name a file

The error prints `pascal26:531:` with no filename — the trap this project has
already promoted, and the one that put the row in `historic.py` (284 lines,
so it has no line 531 at all).

Six modules under `tsp/` have a line 531:

    ascent.py      az = g * z + zz + push[2]           arithmetic, no call
    bpedit.py      self.step = j                        assignment
    departure.py   target, tol=1000.0)                  <-- 5 positional + kwarg
    __main__.py    ed.add_argument("file", help=...)    kwarg, but 1 positional
    provider.py    else:
    universe.py    (blank)

Only `departure.py` satisfies **both** halves of the diagnostic — more than
four positional arguments AND a keyword. The identification is by ELIMINATION
plus construct match, not by the line number, which is what the line number
cannot support.

## What is NOT established

The mechanism. `aim` enters through a **function-local** relative import at
`departure.py:519` (`from .anchor import aim`), and the diagnostic turns on the
callee being a **callable value** rather than a known function. Through
`historic.py`, `anchor` is already bound at module level by line 26. That would
explain why the entry point changes the outcome — **and nothing here tested
it.** Do not start from it; start from the two compiles above, which are facts.
