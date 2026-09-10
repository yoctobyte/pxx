---
slug: bug-n-the-class-body-scope-is-wired-into-the-wrong-one-of-two-doors
title: the class-body scope is consulted in the method BODY and not in the method's DEFAULTS — exactly inverted from Python
track: N
type: bug
prio: 60
status: open
summary: >
  Two doors resolve a bare name for a method, and the class-body scope is wired
  into precisely the wrong one of them. A DEFAULT ARGUMENT falls through to
  module scope and never sees the class body; a method BODY sees the class body
  and prefers it over module scope. CPython is the exact opposite on both. Two
  of the four rows are SILENT WRONG ANSWERS, not refusals.
---

## The measurement

Binary 1266f201c140, 2026-09-10. Each row its own file.

| | pxx | CPython |
| --- | --- | --- |
| default arg, name at BOTH module and class scope | **99** (module) | **14** (class) |
| method body, name at BOTH scopes | **14** (class) | **99** (module) |
| method body, module scope only | 99 | 99 |
| default arg, class scope only | **refused**: `undefined variable (MARGIN)` | 14 |

    MARGIN = 99
    class P:
        MARGIN = 14
        def __init__(self, left=MARGIN): ...   # pxx 99, CPython 14
        def show(self):     return MARGIN      # pxx 14, CPython 99

## Why it is ONE fact and not two

Python's rule is a single one: **a class body is not an enclosing scope for a
function, but it IS the current scope while the `class` statement executes.** So
a method's defaults — evaluated at def time, i.e. during the class body — see
class-level names, and the method's BODY, running later, does not and falls to
module scope.

We consult the class body in the body and not in the defaults. That is the one
rule inverted, not two independent gaps, and it means **a fix to either row
alone leaves the two doors disagreeing in a NEW way rather than the current
one** (`devdocs/dev/normalise-dont-special-case.md`). The repair is one scope
decision serving both doors.

frankB reached this from the write-up alone, without a build, and proposed the
probe that settles it: give the name BOTH scopes and see which wins. That is
what rows 1 and 2 are.

## The two rows that matter most are silent

Row 4 is loud and is the one that blocks lekkerzeilen ui.py:1376. Rows 1 and 2
produce a **plausible wrong integer with no diagnostic**, which is the expensive
class here. Ranked at 60 for that reason, not for the refusal.

## CORRECTION — this was filed as an upward-compatible FEATURE and it is not

An earlier version of this ticket, and an entry added to
`devdocs/dev/nilpy-semantics-divergences.md`, recorded row 2 as NilPy accepting
what CPython rejects — a feature on track N. **That was wrong, and the reason it
looked right is a probe-choice error worth keeping.**

The original probe had NO module-level `MARGIN`, so CPython raised `NameError`
and we returned 14. Against that probe the two possible readings —
"we accept more than CPython" and "we answer with the wrong scope" — produce the
IDENTICAL observation. Adding the module-level name separates them instantly and
the answer is the second one. CLAUDE.md: *choose a probe whose right answer
differs from the default*; here the absent name made CPython's error and our
wrong value look like a widening.

The divergences entry has been withdrawn.

## What is in the tree (measured), and what is NOT

- `FindClassVar(ci, name)` — `compiler/pasparser_class.inc:106`, walks the parent
  chain.
- `FindVarSym(name)` — same file, line 123: `FindSym` plus a class-var arm gated
  on `(CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0)`. This is very likely
  the BODY door, i.e. the one that should NOT be consulting the class.
- `PyClsEvalCi` — `compiler/pyparser.inc:276`. Method defaults are evaluated
  after `PyParseClass` returns, so the class ci IS available at that point.
- `PyEvalParamDefault` — `compiler/pyparser.inc:7039`.

NOT measured: which routine each door actually resolves through. Print it
(`PXXDBG`) before writing a fix.

REFUTED, so nobody re-runs it: `PyEvalParamDefault`'s `savedCurProc := CurProc;
CurProc := -1` looks like the cause because `FindVarSym`'s arm needs
`CurProc >= 0`. It is not — that clearing wraps only the `AllocVar` call that
forces a BSS global, not the `PyParseBoolExpr` that resolves the name. Lines
7088-7107.

## Where it bites

lekkerzeilen `ui.py:1376`, `def __init__(self, left=MARGIN, top=MARGIN, ...)`.
First-wall position only — nothing here says ui.py is one fix from clean.
