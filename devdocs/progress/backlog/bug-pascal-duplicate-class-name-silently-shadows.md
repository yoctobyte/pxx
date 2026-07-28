---
summary: "Pascal: a duplicate class declaration silently binds to the earlier one instead of erroring"
type: bug
track: P
prio: 50
---

# Pascal: a second class with the same name is not diagnosed

- **Type:** bug (Pascal frontend, class registration / diagnostics) — **Track P**
- **Status:** backlog
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
