---
slug: bug-n-the-compiler-segfaults-on-lekkerzeilen-vessel-py
title: deterministic SIGSEGV compiling lekkerzeilen/vessel.py
track: N
type: bug
prio: 75
status: open
summary: >
  The compiler segfaults (rc=139, core dumped, 3/3 runs) on
  lekkerzeilen/vessel.py. lekkerzeilen/traffic.py fails only because it imports
  vessel, so this is ONE defect blocking two modules. Predates 2026-09-10's
  changes — reproduced on f45ed34d4012, the binary a green test-nilpy tier ran
  on — so no test row reaches the shape. A crash, not a wrong value: it has a
  location and is the cheap case, but it is unmissable for the umbrella.
---

## The measurement

    $ ./compiler/pascal26 lekkerzeilen/vessel.py /tmp/o.bin ; echo $?
    Segmentation fault (core dumped)
    139

Three runs for three, identical. `traffic.py` gives the same because
`traffic.py:44` is `from . import vessel`.

Last diagnostics before the crash, which are warnings and not obviously the
cause:

    pascal26:245: warning: several unrelated classes declare a .up property —
                  reading it through the receiver at run time
    pascal26:317: warning: no class declares a method or callable field .wind()
                  — dispatching on the receiver at run time   (x3)

## Not mine, and not 708555fdb — bisected

Reverting `compiler/pyparser.inc` and `compiler/pasparser_call.inc` to
`5fb6e3d57` in one move — which backs out `98ce0b129` (the `OwnFieldBeatsSym`
NilPy gate), `f3cc8525a` (the class-body defaults door) and frankB's
`708555fdb` (dead-path imports) together — and rebuilding gives
**`f45ed34d4012`, which segfaults identically.**

That binary is the one a **GREEN `test-nilpy` tier** ran on the same evening.
So the suite does not reach this shape at all, which is its own small finding:
a deterministic compiler crash on real corpus code that no test row touches.

## Ranking

**75, and it is a crash rather than a wrong value**, which normally makes it the
cheap case — it has a location. It is ranked here because it is the only
CRASH in the lekkerzeilen corpus (every other wall is a missing import or an
unresolved member) and because `vessel.py` is the physics core: the umbrella's
target is a program that RUNS, and two modules cannot compile at all.

## NOT YET MINIMISED — recorded so the next reader does not assume it was

`vessel.py` is 1392 lines and nothing here narrows it. What I would try, in
order, and why:

1. **Bisect the FILE, not the compiler.** Halve it and keep the half that still
   crashes. Cheap, mechanical, and it does not need a theory.
2. The two warned constructs are the obvious suspects and should be treated as
   suspects, not as findings — a `.up` property ambiguous across unrelated
   classes, and a `.wind()` call no class declares. Both are receiver-dispatch
   paths and both are reachable from `PyMakeVariantPropRecv` /
   `PyMakeDynMethCall`. **A warning printed before a crash is adjacency, not
   causation**, and the last line before a segfault is where the compiler last
   spoke, not where it died.
3. `-dPXX_HEAP_DEBUG` and gdb on the core, which is what would actually answer
   it. `make pxx-debug` forces `-O0`, so do not quote its profile as `-O2`.

## Why it was not found until now

The lekkerzeilen census harness classified it as an ordinary wall with an EMPTY
reason, because it decided pass/fail by grepping stderr for
`pascal26:<n>: error:` and a segfault emits no such line. Banked separately in
`debugging-playbook.md` — classify on `rc` first, then parse for detail; a
harness that reads output to decide pass/fail cannot see a failure whose
signature is the ABSENCE of output.

## OPEN QUESTION — how far back does it go?

Established: it reproduces on `f45ed34d4012` (tree `5fb6e3d57`), so it predates
everything landed on 2026-09-10 by this seat and by frankB's `708555fdb`.

**NOT established: whether it predates `1266f201c140`**, the binary the previous
lekkerzeilen census ran on. That matters, and not only for tidiness — the census
reconciliation in `devdocs/progress/census/lekkerzeilen-baseline.md` shows
`vessel.py` and `traffic.py` accounting for -2 clean modules against that older
run. If the crash was introduced in `1266f201c140..f45ed34d4012` then it is a
REGRESSION in a narrow, bisectable window and should be ranked as one; if it is
older, it is a long-standing gap the corpus only just started exercising.

Deliberately left open rather than guessed. Two builds would answer it and the
box was a peer's at the time. **Whoever takes this: the file-bisection in the
section above is still the better first move** — it needs no theory and it
narrows the defect, where an age-bisect only narrows the blame.
