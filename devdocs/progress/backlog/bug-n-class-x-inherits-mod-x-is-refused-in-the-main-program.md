---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`class X(mod.X)` — a class whose qualified base shares its name — is refused with `class X cannot inherit from itself` when written in the MAIN PROGRAM. The identical code in a pulled `.py` module compiles and dispatches correctly, and renaming either class makes the program case work too, so the variable is the name collision on the program path. This is how all ~100 of CPython's `encodings/*.py` and html5lib's filters are written."
---

# `class X(mod.X)` is refused in the main program (works in a module)

- **Type:** bug (NilPy frontend, class registration / qualified base) — **Track N**.
- **Found:** 2026-08-17, in a ladder re-scan of the fetched corpora at
  `63d80e8fc`. Three of html5lib's filters
  (`optionaltags.py`, `alphabeticalattributes.py`, `inject_meta_charset.py`)
  report it.
- **Not a regression.** A/B'd against the pinned compiler
  (`47836e63`): identical message on both. It surfaces in this scan only
  because `-Fu` now lets `from . import base` resolve, so these files get far
  enough to declare the class at all.

## Repro — six lines

```
base.py    class Filter(object):
               def go(self):
                   return 1

main.npy   from . import base

           class Filter(base.Filter):
               def go(self):
                   return 2

           print(Filter().go())
```

| | |
| --- | --- |
| CPython | `2` |
| pxx | `pascal26:3: error: Nil Python: class Filter cannot inherit from itself — a base class must not be the class being declared, nor one of its descendants` |

## Three controls, and together they name the variable exactly

| case | result |
| --- | --- |
| main program, base named `Filter` (as above) | **refused** |
| main program, base renamed `Basic` — everything else identical | **works**, prints 2 |
| main program, `import base` instead of `from . import base` | refused, identically |
| the SAME two files as a package, `sub.py` pulled as a MODULE | **works**, prints 2 |

So it is neither the import spelling nor the qualifier: it is **the name
collision, on the main-program path only.** A pulled module handles the same
declaration correctly.

## Relation to the already-resolved hang

This is the residue of
[[bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler]] (resolved
2026-08-15, `5fd842e6a`). That ticket's cycle guard is what is firing here, and
it is doing its job — it turned an infinite loop into a diagnostic, which is
exactly what it was added for. What is left is that the *lookup* it guards still
answers wrongly on this path.

That fix had two resolution halves worth re-reading before touching this:

1. a forward class stub is filled only by its **own** unit
   (`UClsForward[ci] and (UClsUnitIdx[ci] = CurrentUnitIdx)`) — `parser.inc`,
   Track A ground;
2. a QUALIFIED base resolves in the named module via
   `FindUClassInUnit(name, baseQUnit)`, so a same-named class being declared
   here cannot be the answer — `pyparser.inc`, Track N.

Half 2 is the one that should already prevent this and evidently does not fire
when the qualifier is a **`.py` module** pulled into the **main program**
(`CurrentUnitIdx = -1`). Check whether `ConsumeUnitQualifier` captures the
module in that case before assuming the bug is in the lookup itself.

**If the fix turns out to be in `parser.inc`, that half is Track A — file it,
do not edit it under N.**

## Priority note — it does NOT block the corpora, and that is measured

Set at 45 rather than 55 deliberately. html5lib's filters are **imported** in
real use, never run as programs, and the module path works. The scan reports
them because its method compiles every file standalone. So this is a real defect
on a real shape (`class X(mod.X)` is how essentially all of CPython's
`encodings/*.py` are written) but it is not on the critical path for
[[feature-nilpy-thirdparty-libraries-as-targets]].

## Method caveat this exposed, worth carrying to every future ladder scan

**Compiling each file standalone reports failures that real usage never hits.**
Every scan recorded in the campaign ticket uses that method, and its counts
should be read with this discount: a library file is a MODULE, and the module
path and program path are demonstrably different code paths in this frontend —
this is the third defect today that lives on exactly that seam. The scan is
still the right cheap instrument; it just measures an upper bound on the walls,
not the walls a consumer meets.

## Gate

`make compiler/pascal26` + the six-line repro answering `2`, + all four control
rows above unchanged (especially: the pulled-module case must still work, and
the cycle guard must still fire on a genuine `class X(X)` —
`test/test_nilpy_class_inherits_itself_fail.npy` covers that and must stay red
in the right way), then `tools/gate.sh quick` **before committing** so the FPC
seed canary runs.

Stretch check: `html5lib/filters/optionaltags.py` compiles standalone.
