---
slug: bug-n-a-class-level-name-is-not-visible-in-a-method-s-default-argument
title: a class-level name used as a method's default argument is undefined
track: N
type: bug
prio: 45
status: open
summary: >
  `class P: MARGIN = 14` then `def __init__(self, left=MARGIN)` fails with
  `undefined variable (MARGIN)`. Python evaluates a method's defaults in the
  CLASS BODY's namespace, where the class attribute being defined IS in scope --
  which is why the same name is NOT visible inside the method body. lekkerzeilen
  ui.py:1376 is the live case and it is that module's current first wall.
---

## Repro, and the three neighbours that already work

    class P:
        MARGIN = 14
        def __init__(self, left=MARGIN, top=MARGIN):   # pascal26: undefined variable (MARGIN)
            ...

Measured 2026-09-10 at binary 1266f201c140, each as its own file:

| shape | pxx | CPython |
| --- | --- | --- |
| class attr as a method DEFAULT | **undefined variable (MARGIN)** | 14 |
| `self.MARGIN` in a method body | 14 | 14 |
| MODULE-level constant as a default | 14 | 14 |
| bare `MARGIN` in a method BODY | 14 | **NameError** |

The last row is the interesting control: it is us accepting what CPython
rejects, which is a FEATURE here (CLAUDE.md, track N) and NOT to be "fixed" --
recorded below so nobody reads it as part of this bug. It also shows the
class-var machinery is reachable from a method body, so this is not a missing
registry; it is a scope that is not consulted at the one point Python says it
should be.

## Why the rule is what it is

A method's default expression is evaluated ONCE, when the `class` statement
executes, in the class body's own namespace. So a name being defined in that
body is in scope for a default and out of scope for the method's body. Both
halves are the same rule and we currently have exactly the wrong half of it.

## What is already in the tree (measured)

- `FindClassVar(ci, name)` -- `compiler/pasparser_class.inc:106`, walks the
  parent chain so an inherited class var resolves too. This is the lookup that
  is wanted.
- `FindVarSym(name)` -- same file, line 123: `FindSym`, plus the class-var arm,
  and that arm is GATED on `(CurMethClass >= REC_UCLASS_BASE) and (CurProc >= 0)`.
- `PyClsEvalCi` / `PyClsEvalLo` / `PyClsEvalHi` -- `compiler/pyparser.inc:276`.
  Its own comment says method defaults are evaluated AFTER `PyParseClass`
  returns, because that is the semantically correct point. **So the class's ci
  is known at evaluation time**, which is what makes this look small.
- `PyEvalParamDefault` -- `compiler/pyparser.inc:7039`, parks the cursor, calls
  `PyParseBoolExpr` at the default expression, restores by RE-READING Tokens[].

## What is NOT measured, and it is the first thing to do

**Do not start from the paragraph above.** Two links are unverified and one
plausible-looking hypothesis has already been refuted here:

1. Whether the NilPy bare-identifier path reaches `FindVarSym` at all, or
   resolves through its own lookup and raises `undefined variable` before it.
2. What `CurMethClass` actually holds during the deferred evaluation. The
   expectation is "not the class, because PyParseClass has returned", and that
   is a guess.

REFUTED already, so nobody re-runs it: `PyEvalParamDefault` does contain
`savedCurProc := CurProc; CurProc := -1;` and that looked like the cause, since
`FindVarSym`'s arm needs `CurProc >= 0`. It is not -- the clearing wraps only
the `AllocVar` call that forces a BSS global, not the `PyParseBoolExpr` that
resolves the name. Read lines 7088-7107 before believing otherwise.

Print what `CurMethClass` and the resolution path actually are before writing
any fix. `PXXDBG` exists for this.

## Divergence to record separately, NOT part of this fix

Bare `MARGIN` inside a method BODY returns 14 where CPython raises `NameError:
name 'MARGIN' is not defined`. Upward-compatible, deliberate, and it belongs in
`devdocs/dev/nilpy-semantics-divergences.md` -- it is not there as of this
writing.

## Where it bites

lekkerzeilen `ui.py:1376`, `def __init__(self, left=MARGIN, top=MARGIN,
size=SIZE, visible=True)`. It is that module's first wall as of binary
1266f201c140, reached only after the comprehension own-iterable scope fix
(`3a594228b`) cleared the previous one at 683. First-wall position only: nothing
here says ui.py is one fix from clean.
