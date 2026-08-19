---
track: A
prio: 45
type: task
status: working
owner: frank3
---

# Carve NilPy's lvalue/member parsing out of `parser.inc` (split 2)

**Lane: this is Track A structural work, not deferred Track N work.** The shared
`parser.inc` is A's ground; the carve serves the owner's reduced-compiler ask and
deletes the bare-vs-selector double case that has already produced three bugs. The
standing mandate defers Track N *features and bugs* — NilPy-motivated is not
NilPy-owned, and A's own structure is not deferred by it.

## This campaign now has an objective finish line

Measured 2026-08-19 by
[[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]], which
tried to omit the NilPy frontend and could not:

> **176 NilPy symbols are still called from the shared `parser.inc`, at 426 sites.
> `-dPXX_NO_NILPY` compiling clean IS "carve complete."**

That is the property this campaign lacked. "Fewer guards" is a direction; a compiler
that builds without the frontend is a test. Heaviest remaining callers, i.e. the best
targets after this split: `PyParseBoolExpr` (23 sites), `PyCallMeth1` (19),
`PyAugBinTok` (12), `PyIsIdent` (9), `PyForceVariant` (9), `PyStoredName` (8),
`PyParseSliceTail` (8), `PyMakeDynAttrSet` (8), `PyHoistPark` (8).

Split 2 of the campaign opened by
`task-a-carve-nilpy-selectors-out-of-parser-inc`, which landed split 1
(`ParseClassRecordSelectors` → `PyParseClassRecordSelectors` in `pyparser.inc`,
0 regressions over the 513-file `.npy` sweep, self-host byte-identical). Read
that ticket's Progress section first — it records the method that worked and,
more usefully, the arms that are NOT safe to delete and why.

## Target

`ParseLValueAST`. It is the **sibling path** to the routine already split: a
bare-identifier receiver (`c.m`) goes through `ParseLValueAST`, and every other
receiver shape (`C().m`, `objs[0].m`, `a.b.m`) goes through
`ParseClassRecordSelectors`. Two parsers for one construct.

## Why this one, beyond the guard count

This split has a payoff the first one did not. The bare-vs-selector divide has
produced at least three separate bugs where one path learned something and the
other stayed broken — a class-attribute read through a non-bare receiver, a
bound-method value that segfaulted on a temporary receiver, and a chained
subscript that ignored its index (`project_nilpy_lvalue_vs_selector_path_must_both_know`,
`devdocs/dev/normalise-dont-special-case.md`). The recurring fix is "teach both",
which is exactly the thing nobody remembers to do.

Once BOTH selector paths are NilPy-only routines, they can share a NilPy-side
member-resolution helper — which is the real fix for the double case. That is
impossible while each is entangled with the Pascal arm it sits next to. So the
carve is not only hygiene here; it is the precondition for deleting the double
case.

## Method (proven by split 1)

1. Copy the routine into `pyparser.inc` under a `Py`-prefixed name.
2. Dispatch to it from the top of the Pascal original on `PyExprMode`, so every
   call site is untouched.
3. In the copy, fold `PyExprMode` / `isNilPy` / `NilPyUserCode` to `True` — this
   is provable (`PyExprMode` is set only by `pyparser.inc`), which keeps the
   split a pure restructuring with no reachability change in either dialect.
4. In the Pascal original, delete **only** the `PyExprMode`-guarded arms. Do NOT
   delete `isNilPy` or `NilPyUserCode` arms: with `PyExprMode` false they are
   still reachable — `isNilPy` holds while parsing the Pascal RTL units an
   `.npy` program pulls in, and `NilPyUserCode` reduces to
   `isNilPy and (CurrentUnitIdx < 0)`, true during the main program's
   pre-`PyExprMode` phase. Deleting them is a behaviour change wearing a
   refactor's clothes.
5. Prune variables the deletions orphaned, or FPC's `-vw` will say so.

## Gate

`make compiler/pascal26` (the fixedpoint — the strong oracle for the Pascal
half) + `tools/gate.sh quick` + a whole-suite HEAD-vs-pinned `.npy` sweep
(`/tmp/sweep/regress.sh`; recreate from split 1's ticket if gone). The sweep is
not optional here: a carve-out is a NARROWING change and cannot be
regression-tested by the tests that motivated it. Also run the FPC seed build by
hand — adding a routine is not covered by `make` or `gate.sh`.

## After this

Remaining `parser.inc` guard counts to drive down: `PyExprMode` 125, `isNilPy`
67. Some are genuinely shared (a NilPy-only *diagnostic* on a shared construct);
the test is whether the two dialects want different SEMANTICS, not merely a
different message.
