---
track: A
prio: 65
type: bug
blocked-by: []
summary: "The escape hatch the new bare-import diagnostic RECOMMENDS does not work for the unit that motivated the feature: `import 'classes.pas' as cl` from NilPy dies at classes.pas:1060 with `no overload of Delete matches these arguments (Integer)`, while Pascal's own `uses classes;` compiles the identical file fine. Same message, same line, as the failure feature-a-a-bare-nilpy-import-* was filed to fix."
status: done
owner: frank3
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

---

## ROOT CAUSE (frank3, 2026-08-19) — `isNilPy` again, and it is not the import path

**Not the escape hatch, and not `classes.pas`.** The bisect that settled it, in one step:

    program p; uses './lib/rtl/classes.pas' as cl;   ->  OK
    import './lib/rtl/classes.pas' as cl             ->  FAILS

**Same file, same quoted path, same alias machinery, same pin — only the frontend differs.**
So the quoted import arm is exonerated and the variable is the NilPy compilation. That also
means this bug is **pre-existing, not introduced**: it is the *original* symptom from
[[decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit]] ("`from classes import Foo` ->
no overload of Delete"), which was read as an import-resolution problem. It never was. Fixing
resolution moved the wall one step and left this behind it, which is why it looked like a new
hole in the feature.

### The mechanism

`parser.inc` implements FPC's scoping rule — *inside a method, the enclosing class's own
method shadows a same-named plain proc from a used unit* — and disables it under `isNilPy`,
for a real reason: in Python a bare name is never a method, so a method delegating to a
module-level function of the same name must call the FUNCTION (songformatter's
`def select_image(self): select_image()`, which otherwise recurses into itself).

**But `isNilPy` is true for the WHOLE compilation, including every Pascal RTL unit a NilPy
program drags in.** `lib/rtl/classes.pas` `uses sysutils`, which declares
`Delete(var s: AnsiString; index, count: Integer)`, and `TStrings.SetValueFromIndex` calls its
own abstract `Delete(Index)` bare — so under NilPy the shadow rule was off, the call bound
sysutils' proc, and the unit could not compile at all.

**This is the third instance of one predicate defect in this lane in one day**, and the
codebase already carries the right answer: `NilPyUserCode` (`symtab.inc:25`), whose own
doc-comment says it exists because `isNilPy` "is true for the WHOLE compilation", and whose
`PyExprMode` term distinguishes an imported `.py` module body from a Pascal unit. Both twin
sites now use it.

**Both twins moved together** — the expression-side and statement-side guards carry each
other's cross-reference, and a fix to one arm of a double case that skips the sibling is how
this family of bug survives.

### Why it was invisible

`classes.pas` had already met this hazard at ONE site and worked around it locally:

    lib/rtl/classes.pas:708   if Result >= 0 then Self.Delete(Result);   { Self. — Delete is also a builtin }

A `Self.` qualifier at line 708 and a bare call at line 1059, same unit, same method name.
The workaround made the first site work and left no signal that the rule itself was wrong.

### Verified, all four directions

    import 'classes.pas' as cl                     ->  compiles, runs
    NilPy method delegating to a module function   ->  returns the FUNCTION's 7, no recursion
    the same shape inside an imported .py module   ->  returns 9 (PyExprMode keeps Python's rule)
    program p; uses classes;                       ->  unchanged

Regression test `test/test_nilpy_pascal_unit_keeps_fpc_method_shadowing.npy` pins the first
two in one file, deliberately: the fix moves a single predicate and **either direction alone
is wrong**, so a test that checks only one would pass for the broken opposite.

### Correction to my own note on the parent ticket

[[feature-a-a-bare-nilpy-import-means-python-and-another-language-needs-its-extension]] says
`NilPyUserCode` "goes false inside an imported `.py` module". **That is wrong** — `PyExprMode`
is exactly what keeps it true there. The import work's design is unaffected (recording the
fact at the call site is right either way, since neither predicate answers "did this `uses`
come from an import statement"), but the stated reason was half wrong and is corrected here.

## Gate

`make compiler/pascal26` (fixedpoint, converged) + `tools/gate.sh quick` GREEN.
- 2026-08-19 — resolved, commit cc95bf083.
