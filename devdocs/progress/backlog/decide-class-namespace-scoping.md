---
track: U
prio: 65
type: decide
---

# Decide: how should two libraries be allowed to export the same class name?

Raised 2026-07-28 from [[feature-demo-songformatter-pxx-target]], where it is the
blocker: `convertrawtext.py` imports tkinter AND reportlab, both of which export a
class called `Canvas`, and both spellings are fixed by the applications that use
them. Python scopes them per module. pxx has ONE flat class namespace, resolved
first-match (`FindUClass`, `compiler/symtab.inc`).

## The fork

Two same-named classes can mean two opposite things, and today's rule cannot tell
them apart:

- **Two independent classes** — `tkinter.Canvas` and `reportlab`'s `Canvas`. Each
  unit wants ITS OWN. First-match gives the name to whichever unit was registered
  first, so the second unit's own methods bind to the first unit's class and
  report their own fields as undefined variables.
- **One class, deliberately merged** — pylib's `Exception` and sysutils'
  `Exception`. The tree RELIES on these being the same class, and they are the
  same class only *because* first-match hands pylib's row to everyone. A NilPy
  program catches what an RTL unit raises exactly for that reason
  (`test_nilpy_rtl_exception_surface`).

Preferring "the class declared in the unit being parsed" was implemented and
reverted: it fixes the first case and breaks the second, turning a compile error
into a **silently uncaught exception**. Details and the exact failure are in
[[bug-pascal-duplicate-class-name-silently-shadows]].

## Options

1. **Make the merge explicit, then scope per unit.** A class states that it
   replaces a same-named one (`Exception = class ... ; replaces system.Exception`
   or a pragma), and every other name becomes unit-scoped. Most correct, and the
   only one that lets two libraries coexist. Cost: an RTL change plus a new piece
   of language surface, and every existing accidental merge has to be found.
2. **Unit-scoped classes, with the RTL merges hard-coded.** Same effect without
   new syntax: a short list in the compiler naming the classes that are
   deliberately shared. Cheap, and it is a list that will rot.
3. **Leave it flat; make the collision an ERROR rather than a silent capture.**
   Honest and small, but it does not let songformatter compile — tkinter plus
   reportlab is simply rejected. It would at least stop the silent-wrong-binding
   case, which is the dangerous half.
4. **Do nothing.** Today's behaviour: first-match wins, collisions are silent.

## Recommendation

Option 1, with option 3 landed first as a stopgap — the silent binding is the
part that can produce wrong output, and making it loud is independently correct
and small. The qualified-reference case is the sharpest edge: renaming the shim's
class made `canvas.Canvas(...)` bind to tkinter's `Canvas` and compile clean.

## Scope note

This is not only a NilPy question. It is the Pascal class namespace, so any two
Pascal libraries with a same-named class have it; NilPy just meets it sooner
because Python code imports several libraries into one module as a matter of
course.
