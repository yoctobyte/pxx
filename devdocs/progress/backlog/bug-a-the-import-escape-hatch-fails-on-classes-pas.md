---
track: A
prio: 65
type: bug
blocked-by: []
summary: "The escape hatch the new bare-import diagnostic RECOMMENDS does not work for the unit that motivated the feature: `import 'classes.pas' as cl` from NilPy dies at classes.pas:1060 with `no overload of Delete matches these arguments (Integer)`, while Pascal's own `uses classes;` compiles the identical file fine. Same message, same line, as the failure feature-a-a-bare-nilpy-import-* was filed to fix."
---

# `import 'classes.pas'` still dies on `Delete` — the escape hatch does not clear the wall

- **Type:** bug (Track A — the shared import/resolution path in `parser.inc`).
  Filed by Track D while documenting the new import rules; not fixed here.
- **Found:** 2026-08-19 against pin **v364** (`955a713467cd39297cb590a80b7f08d3`).

## What the compiler tells the user to do, and what happens when they do it

The new bare-import diagnostic is excellent and ends with an instruction:

```
$ pxx t.npy t          # t.npy:  import classes
error: import: classes is the Pascal unit …/lib/rtl/classes.pas, not a Python
module — a bare NilPy import resolves to Python (.py/.npy) only. To reach the
Pascal unit, name it with its extension: import 'classes.pas' as classes
```

Following that instruction fails:

```
$ pxx t.npy t          # t.npy:  import 'classes.pas' as cl
pascal26:1060: error: no overload of Delete matches these arguments
  argument types: (Integer)
  candidates:
    Delete(AnsiString, Integer, Integer)
  near:  then Delete  Index  >>> else Put
```

`classes.pas:1058` is `if Value = '' then Delete(Index)` inside
`TStrings.SetValueFromIndex` — a bare call to the class's **own** method
`TStrings.Delete(Index: Integer)` (declared at 234/278/381). Through the NilPy
import path it binds to the global string `Delete` intrinsic instead, so method
scope is lost.

**The same file compiles fine from Pascal.** `program uc; uses classes; begin
WriteLn('ok'); end.` builds clean on the same pin. So this is the import path,
not `classes.pas`.

## Why it matters more than one unit

This is the *motivating* unit. `feature-a-a-bare-nilpy-import-and-another-language-needs-its-extension`
was filed to fix "`from classes import Foo` failing with a message about
`Delete` inside a Pascal unit the program never mentioned". The bare-import
half landed and is a real improvement — the message now names the cause. But
the escape hatch it points at walks into the *same wall, at the same line, with
the same message*. From a user's seat the feature is not finished: they are
told what to type, they type it, and they get the original error.

`import 'sysutils.pas' as su` **works** (`su.Trim('  hi  ')` prints `hi`), so
the mechanism is right in general and something about this unit trips it.

## What did NOT reproduce it — narrowed, not solved

Two minimal units were built and both compile clean through
`import './x.pas' as m`, so the obvious hypotheses are wrong:

- a class method named `Delete(Index: Integer)` called bare from a sibling
  method of the same class;
- the same, with `Delete` declared `virtual; abstract;` in the base.

Varying the alias (`as cl` vs `as classes`) and importing `sysutils.pas` first
change nothing. Whatever selects the global overload needs something else
`classes.pas` has — bisect the unit rather than guessing.

## Suggested first probes

- `PXXDBG=a.ast:TStrings.SetValueFromIndex` on both paths (Pascal `uses` vs
  NilPy `import`) and diff what the call node resolved to. Measure, do not
  reason: the compiler knows the answer and printing it is cheaper than a
  theory.
- Check whether the NilPy path leaves a global `Delete` in scope that the
  Pascal path does not, and whether method scope is consulted first in one and
  second in the other.

## Log
- 2026-08-19 — filed from a Track D documentation pass over the new import
  rules.
