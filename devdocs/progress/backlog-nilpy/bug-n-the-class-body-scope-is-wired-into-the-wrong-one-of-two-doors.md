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

## MECHANISM — proven from the AST, no build needed

`PXXDBG=a.ast:P.show` on the two body cases settles what the body door does:

    MARGIN = 99 only          `return MARGIN` -> AN_IDENT(536)          <- module global
    MARGIN = 99 AND class 14  `return MARGIN` -> AN_FIELD(AN_IDENT self, "MARGIN")

So the bare name is **rewritten at COMPILE TIME into an implicit `self.MARGIN`**
whenever the enclosing class has an attribute of that name, and only falls
through to ordinary scope resolution when it does not. This is not the
`FindVarSym`/`FindClassVar` class-var registry at all — that guess is dead.

The precedence today, measured (locals/params/loop vars each in their own file):

    local  >  parameter  >  loop var  >  CLASS ATTRIBUTE  >  module global

CPython's, for a method BODY:

    local  >  parameter  >  loop var  >  module global        (no class attribute anywhere)

**Locals, parameters and loop variables all shadow the class attribute
correctly** — so the defect is not "the rewrite is too eager" in general. It is
precisely that the class attribute is inserted at ONE point in the chain where
Python has nothing, between the locals and the module globals, and only the
module global loses.

## The repair this implies

Move the implicit-self rewrite BELOW module-global resolution, making it a
LAST-RESORT fallback rather than a precedence step. That gives:

- name at both scopes -> module global wins -> **matches CPython**;
- name at class scope only -> still resolves to the attribute -> **14, where
  CPython raises NameError**, which is then a genuine upward-compatible widening
  in the only case where it is safe, rather than a wrong value;
- local/parameter/loop var -> unchanged, already correct.

The DEFAULT-argument door needs its own addition and this does not supply it:
defaults are evaluated where no `self` exists, so no implicit-self rewrite can
apply there, and the class-body scope has to be consulted explicitly. One rule,
two doors, and the two halves of the repair are not the same edit.

## OUT OF SCOPE, recorded so it is not mistaken for this bug

    def show(self):
        v = MARGIN        # class MARGIN = 14
        MARGIN = 3
        return v          # pxx 16, CPython UnboundLocalError

A name assigned later in the function is a local for the whole function in
Python, so reading it first is an error CPython names. Our 16 is a wrong value
rather than a wrong diagnostic, but the program is only produced by a mistake --
CLAUDE.md: ask what the source MEANT, and where the two readings differ only
when the program is already wrong, CPython's answer is not a specification.
Not this ticket, and not obviously worth one; noted because it turned up in the
same sweep and looks related.

## What is in the tree (measured), and what is NOT

- `FindClassVar(ci, name)` — `compiler/pasparser_class.inc:106`, walks the parent
  chain.
- `FindVarSym(name)` — same file, line 123: `FindSym` plus a class-var arm gated
  on `(CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0)`. **NOT the body
  door** — the AST proves the body door builds an AN_FIELD over `self`, not a
  class-var symbol read. Left here because it was the obvious suspect and is
  not the answer.
- `PyClsEvalCi` — `compiler/pyparser.inc:276`. Method defaults are evaluated
  after `PyParseClass` returns, so the class ci IS available at that point.
- `PyEvalParamDefault` — `compiler/pyparser.inc:7039`.

NOT measured: which ROUTINE performs the implicit-self rewrite. The AST says
what it produces (`AN_FIELD` over `AN_IDENT self`) and when (only when the class
has that attribute), which is enough to name the repair but not enough to place
the edit. Find the site that builds that node before writing anything.

REFUTED, so nobody re-runs it: `PyEvalParamDefault`'s `savedCurProc := CurProc;
CurProc := -1` looks like the cause because `FindVarSym`'s arm needs
`CurProc >= 0`. It is not — that clearing wraps only the `AllocVar` call that
forces a BSS global, not the `PyParseBoolExpr` that resolves the name. Lines
7088-7107.

## Where it bites

lekkerzeilen `ui.py:1376`, `def __init__(self, left=MARGIN, top=MARGIN, ...)`.
First-wall position only — nothing here says ui.py is one fix from clean.
