---
slug: bug-n-the-compiler-segfaults-on-lekkerzeilen-vessel-py
title: deterministic SIGSEGV compiling lekkerzeilen/vessel.py
track: N
type: bug
prio: 75
status: done
summary: >
  FIXED. A METHOD's parameter list was bounded at 16 (array[0..15] in
  PyRegisterClassMembers and PyParseMethod) while a top-level def's was bounded
  at 32, and the only bound on either method fill loop sat inside `if isGenM` —
  so a NON-generator method of 17 parameters wrote one past the end and took
  the compiler out. Vessel.__init__ has 23. Both arrays now run to
  MAX_PROC_PARAMS and both loops carry the unconditional guard the def path
  always had. vessel.py compiles; traffic.py, which only imports it, now
  reaches a real diagnostic. Census CLEAN 20 -> 21, CRASH 2 -> 0.
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

## THE CAUSE

`compiler/pyparser.inc`, two routines that build the same parameter list:

  * `PyRegisterClassMembers` — the member pre-pass, which decides the
    REGISTERED signature (`pnames`, `ptypes`, `pdefHas`, `pdefIsStr`,
    `pdefIsNone`, `pdefIsFloat`, `pdefIsBool`, `pdefVal`, `pdefSOff`,
    `pdefSLen`, all `array[0..15]`);
  * `PyParseMethod` — which builds the FRAME (`pnames`, `ptypes`, `pcis`,
    `psigs`, all `array[0..15]`).

Both fill loops write `x[nparams]` and `Inc(nparams)` with no bound. A bound
exists and is correct — `if nparams >= 15 then Error('too many parameters for a
generator method')` — but it is inside `if isGenM` / `if isGenDef`, so **only a
method whose body yields was ever checked**. `PyParseDefHeader`, the top-level
def path, has always had an unconditional `if PyHdrNParams >= 32`, which is why
a free function of 24 parameters compiles and a method of 17 does not.

The discriminator, and it is one line apart:

    class C:
        def m(self, p0..p15):   # 17 including self
            yield 1             # -> clean diagnostic
            return 1            # -> SIGSEGV

## THE FIX

Both routines' arrays now run to `MAX_PROC_PARAMS - 1`, and both loops carry
the same unconditional guard the def path has, at the same bound. The def
path's bare literal `32` now names `MAX_PROC_PARAMS` too, so the three move
together — the file's own comments record that when the pre-pass and
`PyParseMethod` disagree by one slot the result is a silent ABI mismatch, so
they must not be able to drift apart.

`MAX_PROC_PARAMS = 32` is the pipeline's own limit — `ProcParamIsConst` is
indexed `procIdx * MAX_PROC_PARAMS + i` — so this aligns the method path with
the function path and with the machinery underneath, rather than inventing a
third number.

## THE BOUNDARY, MEASURED

Reduced from 1392 lines to 9, standalone, by ast-guided delta debugging
(122 compiles). The repro needs no package and no imports:

    class Vessel:
        def __init__(self, name, length, beam, draft, freeboard, mass,
                     max_thrust, max_speed, buoyancy_factor=2.0, ...):
            pass

Holding the count and varying the subject:

| shape | 16 total | 17 total | 24 total |
| --- | --- | --- | --- |
| method, no defaults | ok | **SEGV** | **SEGV** |
| method, all defaulted | ok | **SEGV** | — |
| method, not `__init__` | — | **SEGV** | — |
| top-level function | ok | ok | ok |
| Pascal method | ok | ok | ok (25) |

So: any method, `self` included in the count, defaults irrelevant, NilPy only.
**This retires the two warned constructs named below as suspects** — the `.up`
property and the `.wind()` dispatch had nothing to do with it, which is what
the note about adjacency was there to protect against.

## WHAT THE OPEN QUESTION WAS WORTH

The age question ("does it predate `1266f201c140`") was deliberately left open
and **was never needed**: the cause is a fixed-size array with no guard, not a
regression from any commit in the window. File-bisection narrowed the defect in
one run; an age-bisect would have narrowed blame for a bug that has no blame to
narrow. Recording that because the advice to skip it came from a peer and it
was right.

## THE TEST

`test/test_nilpy_a_method_takes_more_than_sixteen_parameters.npy`, wired into
the Makefile beside the other NilPy scope rows. Byte-identical to CPython.
Positive control: the pinned compiler `095ef4811a5b` SIGSEGVs on it.

It asserts parameter VALUES past index 16 rather than the fact that it
compiles — the defect is an array overrun, and an overrun corrupts a parameter
list as readily as it crashes, so a compile-only row would have been the wrong
assertion class. `free_seventeen` is the control: the def path always guarded
at 32, so that row was green throughout and proves the test exercises the
method path.

## The original report follows

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

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c18f92f48.
