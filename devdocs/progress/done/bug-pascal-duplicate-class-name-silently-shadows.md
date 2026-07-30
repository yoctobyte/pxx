---
summary: "Pascal: a duplicate class declaration silently binds to the earlier one instead of erroring"
type: bug
track: P
prio: 50
---

# Pascal: a second class with the same name is not diagnosed

- **Type:** bug (Pascal frontend, class registration / diagnostics) — **Track P**
- **Status:** done
- **Opened:** 2026-07-26.

## This ticket REPLACES a wrong one

It was filed as `bug-pascal-subclass-inherited-members`, claiming four ways
subclassing was broken: inherited fields and methods invisible unqualified, the
inherited constructor resolving to a different `Create`, and the inherited default
property losing subscript assignment. **That report was wrong** and the file is
deleted rather than left to mislead.

What actually happened: implementing `collections.Counter` I declared
`TPyCounter = class(TPyDict)` in `compiler/builtin/pylib.pas` — where **`TPyCounter`
already exists** (pylib line 46, the `itertools.count` iterator). Every symptom was
that collision:

- `indexof` / `FVals` "undefined" — the method bodies bound to the EXISTING
  TPyCounter, which descends from nothing and has neither.
- "not enough arguments to constructor TPyCounter.Create (parameter start has no
  default)" — that is literally the existing `TPyCounter.Create(start: Int64)`.
  The message was telling me the truth and I read it as constructor inheritance.
- `c[k] = v` not parsing — the existing class has no default property.

Subclassing itself works. Verified after the fact, both in a program and in a unit,
and inside pylib against TPyDict: a bare inherited method call, a bare inherited
field read, an overriding method, a re-declared `default` property with subscript
ASSIGNMENT, overloaded methods, and the inherited constructor all behave.

## The real (smaller) bug

Declaring a class whose name is already taken should be an ERROR naming the
collision. Instead the second declaration is accepted and uses of the name bind to
the first, so the diagnostics land far away — in a 4000-line unit that is a long
detour, and it cost real time here.

Note `collections.Counter` shipped as a MODE on TPyDict rather than a subclass
(commit d40a8410). That decision no longer has a technical justification, only a
practical one: as a mode, a Counter IS a dict, so subscript/items/iteration/`dict(c)`
came along free. Worth revisiting only if Counter needs to diverge further.

## Gate

`make test` + self-host byte-identical, with a `test/` case asserting the duplicate
declaration is rejected and names the earlier one.

## Attempted fix 2026-07-28, REVERTED — and what it taught

`FindUClass` returns the FIRST row with a matching name, whatever unit declared
it, so the first unit to register a name captures it everywhere. The obvious fix
— prefer a class whose `UClsUnitIdx` is the unit being parsed, falling back to
first-match — does unblock the case that motivated it: `lib/pcl/tkinter.pas`
declares `Canvas` (the Tk widget) and `lib/pcl/mimic_reportlab_pdfgen.pas`
declares `Canvas` (reportlab's), both spellings are required by the applications
using them, and without the preference the shim's own constructor binds to
tkinter's class and reports the shim's own fields as undefined variables.

**It also breaks exception handling, so it was reverted.** `test_nilpy_rtl_exception_surface`
fails: pylib's `Exception` and sysutils' `Exception` are supposed to be ONE class
here, and they are one only BECAUSE first-match hands pylib's row to everybody.
With the preference in place, sysutils raises its own class and the program's
`except Exception` catches the other one, so `su.StrToInt("abc")` escapes as an
unhandled exception.

The two cases cannot be told apart by a lookup rule: `Canvas` wants per-unit
scope, `Exception` wants a deliberate merge, and nothing in the tables says
which. So the fix needs the merge to become EXPLICIT — a class that means to
replace a same-named one says so — before per-unit scoping can be turned on.
Anything else trades a compile error for a silently-uncaught exception.

**Still unfixed and worse than the declaration side:** a qualified REFERENCE is
first-match too. Renaming the shim's class proved it — `canvas.Canvas(...)` after
`from reportlab.pdfgen import canvas` silently bound to tkinter's `Canvas` and
compiled. A same-named class reached through the wrong unit is silent wrong
behavior, not a diagnostic.

## Consequence right now

`lib/pcl/mimic_reportlab_*` compiles and works on its own, and stops compiling as
soon as an application imports tkinter as well — which songformatter's
convertrawtext.py does. That module is blocked here.

> Instance of [[decide-unit-local-names-leak-to-global-scope]] — unit-local
> names are visible program-wide, so the first registration wins and the answer
> depends on import order. Fixed here at the call site; the root is that ticket.

## FIXED 2026-07-30 — and it caught a live duplicate in our own pylib

On its first full-gate run the check rejected `ZeroDivisionError`, declared
TWICE in `compiler/builtin/pylib.pas` eight lines apart (255 and 263). Nothing
had ever said so. Removed with the fix.

The design below (a "compiler-provided" flag) turned out NOT to be needed — that
note was written from a first attempt that misread the second false positive.
The two things to distinguish from a duplicate are:

- a FORWARD stub. Pascal's `TFoo = class;` already carried `UClsForward` and the
  declaration path already reuses such a row; NilPy's shell pre-pass
  (pyparser.inc) did not set it, so a `.npy` class looked like a redeclaration
  of its own stub. Those rows ARE forward stubs — marking them so is right on
  its own merits, and it removes the whole apparent "open-ended set of
  compiler-registered classes" problem.
- `TObject` / `TGuid`, pre-registered before any source is parsed. A closed set
  of two, excluded by name.

Kept below for the record, since the first attempt's TWO failures are what
pointed at the forward-stub reading.

## First attempt (superseded) — reverted; misdiagnosed as needing a flag

The check itself is a three-line addition at the class-declaration site
(parser.inc, the `else ci := AddUClass(tnOff, tnLen)` arm): if `FindUClass(tname)`
already returns a row whose `UClsUnitIdx` is the current unit, that is a
redeclaration. It works — `TFoo` declared twice in one program is rejected and
names the collision, and a forward stub (`TBar = class;` … `TBar = class`) is
correctly NOT flagged.

It does not survive `make test`, and the two failures are the interesting part:

1. `test/test_object_ref_array_identity.pas` declares its own `TObject`. The
   compiler pre-registers `TObject` and `TGuid` (parser.inc ~27733/27756) before
   any source is parsed, with whatever `CurrentUnitIdx` holds at the time — so a
   user's own `TObject` reads as a duplicate of the built-in.
2. `test/test_nil_python_core.npy` declares `ZeroDivisionError`, and the NilPy
   frontend pre-registers the Python exception classes the same way.

Excluding names by hand (I tried `TObject`/`TGuid`) just moves the whack-a-mole:
the set of compiler-pre-registered classes is not enumerable at the check site,
and every future one silently re-breaks it. Shipping that would reject legitimate
programs to diagnose a rarer mistake — strictly worse than the silence.

**What it needs:** a `UClsCompilerProvided` flag on the class row, set True at
every pre-registration site (the two Pascal roots, the NilPy exception family,
and anything else that calls AddUClass before user source), with the duplicate
check skipping a row that carries it. Then the rule is exact — "the USER declared
this name twice in this unit" — and it stays exact as new built-ins are added.
Audit the AddUClass callers (symtab.inc 710, parser.inc 19196/27733/27756,
pyparser.inc 2495, cparser.inc and rparser.inc sites) when doing it.

Gate for the next attempt: `tools/gate.sh full` — `make test` is what caught both
of these, and `--tier quick` alone does not.

## Log
- 2026-07-30 — resolved, commit 508eb7bc3.
