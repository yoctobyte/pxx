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

## Option 2 implemented as the stopgap (2026-07-28)

Classes are now resolved per unit — a class declared in the unit being parsed
wins — EXCEPT for a named list of deliberately shared names, which today holds
exactly one entry, `Exception`. `ClassNameIsDeliberatelyShared` in
`compiler/symtab.inc` is that list, and it exists because pylib's and sysutils'
`Exception` mean ONE class and the tree relies on it.

This unblocks the reportlab shim next to tkinter, and it keeps
`test_nilpy_rtl_exception_surface` green. It does NOT settle the fork: the list
is exactly the thing that will rot, and option 1 (a class declares that it
replaces a same-named one) retires it. The qualified-reference case is also still
first-match.

So the decision stands open; what changed is that the cost of leaving it open is
now a maintenance list rather than a blocked application.

## 2026-07-28, second look: this is a SYMPTOM, and the fork is a false one

Reviewing the options above against the actual resolver turned up the cause, and
it retires most of this ticket. Filed as [[bug-pascal-uses-is-transitive]].

**`uses` is not transitive in Pascal — and it is in pxx.** If A uses B, a unit
using A must not see B's names, whichever section A imported B in. pxx has one
flat global namespace for routines and for classes, so every unit's imports leak
to its consumers. Measured in pure Pascal, no NilPy involved: a program that uses
only `priv` resolves `IntToStr` although `priv` imported sysutils in its
IMPLEMENTATION section and the program never mentions sysutils at all.

Given that, the "fork" in this ticket is not a language-design question:

- Two independent classes (`tkinter.Canvas` / reportlab's) are only in conflict
  because both live in one namespace. With non-transitive `uses` they are
  different names in different scopes. Nothing to decide.
- One deliberately merged class (`Exception`) needs no merge mechanism either:
  whichever of pylib/sysutils imports the other gets that one class by
  construction, and `ClassNameIsDeliberatelyShared` is deleted.

**So option 1's language surface is unnecessary** — the `replaces` declaration
exists to reintroduce, by hand and per class, the scoping the resolver is
missing wholesale. Option 2 (the current stopgap) stays as-is until the root fix
lands; it is doing its job and costs one list entry.

Also worth recording, since a `replaces`-style re-export may still be wanted for
its own sake: **the FPC spelling already parses.** `type Exception =
excbase.Exception;` goes through the unit-qualified type path
(`parser.inc:18667`, Synapse's `TInAddr6 = sockets.Tin6_addr`) and registers a
`UClsAlias` row. What is missing is plumbing, not syntax — alias rows carry
`NOff/NLen/Ci` only (`defs.inc:2249`), no unit index, so `FindUClassInUnit`
cannot see them and the NilPy qualified-ctor path (`pyparser.inc:2785`) skips
them. No keyword needed.

### Routes considered and rejected

- **`{$ifndef HAS_EXCEPTION}` cooperative guard.** Pragmatic and needs no
  compiler change — but it works only because pxx has a SECOND bug: defines leak
  across unit boundaries, order-dependently
  ([[bug-pascal-defines-leak-across-units]], filed). Fix that and the guard
  breaks. It also makes which declaration wins a function of parse order,
  silently, which is the opposite of what a project mixing Pascal and Python
  modules in arbitrary order wants.
- **Hoist `Exception` into a leaf `excbase.pas`, aliased from both.** Sound, and
  `sysutils.Exception` keeps working (qualified type refs resolve the bare name —
  `parser.inc:18667`). Rejected as premature: it drags `CreateFmt` with it, which
  drags `Format`, which drags `FloatToStr` — and once `uses` scopes properly the
  extra unit buys nothing.
- **`pylib uses sysutils` unconditionally.** Cheapest of all and it works.
  Measured cost is not the problem (`.npy` 855,980B/865 procs → 918,287B/984
  procs, +7.3%). The problem is that with transitive `uses` it pours sysutils'
  exports into EVERY Python program's namespace — and Pascal is case-insensitive
  where Python is not, so `format`, `date`, `time`, `trim`, `pos`, `copy`,
  `delete`, `insert` all shadow. This becomes the right answer, trivially, once
  `uses` scopes.

### Recommendation, revised

Do nothing here. Keep option 2's list. Fix
[[bug-pascal-uses-is-transitive]] (size it first with the warn-only pass
described there) and [[bug-pascal-defines-leak-across-units]], then close this
ticket as resolved-by-cause rather than deciding it.

The one piece NOT covered by the root fix is the qualified-reference case
(`canvas.Canvas(...)` binding first-match, noted above and in
[[bug-pascal-duplicate-class-name-silently-shadows]]) — that needs the alias
unit-index plumbing regardless, and is independent of the decision.

### Side finding, recorded for whoever touches Exception

`Exception.CreateFmt` has TWO bodies — `sysutils.pas:589` (full `Format`:
`%d %u %x %X %s %f %g %c`, width, precision, padding) and `pylib.pas:3612` (a
dependency-free substituter handling `%s`, `%d`, `%%` only, leaving any other
spec verbatim so a wrong message is visible rather than silently lost). Which one
runs is decided by link order. Measured: a `.npy` reaching a Pascal unit that
raises `CreateFmt('hex=%x pad=[%5s]', [255,'ab'])` prints `hex=FF pad=[   ab]`,
so **sysutils' body wins whenever both are linked**; pylib's is the standalone
fallback, and pylib never calls `CreateFmt` itself. No RTL raise site currently
uses a spec outside `%s`/`%d`, so the two agree on everything exercised today —
the divergence is latent, not live. Worth a `%x`-and-width raise added to
`test_nilpy_rtl_exception_surface` to make it a guarded case rather than a
coincidence.
