---
slug: bug-n-a-dead-guarded-import-arm-still-binds-its-unit-alias
track: N
type: bug
prio: 80
status: done
owner: frankZ
created: 2026-09-10
found-by: frankZ
tags: [nilpy, imports, lekkerzeilen, portability, silent-wrong-value]
blocked-by: []
summary: "FIXED 2026-09-10 (compiler `6d53c745ea69`). A `try:` arm killed by a failed guarded import still registered its unit ALIAS, and `FindUnitOrAlias` takes the FIRST row for a name -- so the dead arm's binding beat the handler's binding of the same name and never reported anything. `try: import ctypes; from . import primary as backend / except ImportError: from . import fallback as backend` ran the handler, said `fallback`, and read every `backend.member` off PRIMARY. The sibling half bound the name to None instead (an optional-missing name recorded from an EARLIER import's miss), so the same seam could also fail with `AttributeError: 'NoneType'`. THREE layers had to change: the alias registrations roll back with the block in PyPreScanImports and in PyParseFallbackImportTry (the parser alone measured as NO CHANGE -- the prescan is what registers), and `SoftUnitMissed` is now cleared per import inside PyParseImportRun as PyParseOneImport has cleared it since the tkinter/ttk case, with the run's answer accumulated for the callers that decide the branch. CPython is the oracle and agrees on all three rows including the refusal. CORPUS DELTA: ZERO modules -- lekkerzeilen's seam returns a module as a VALUE and walls on bug-n-a-module-bound-by-an-import-is-not-a-value, unmoved at platform/__init__.py:95. Its worth is that it removes the trap under the obvious repair of that wall."
---

# What it was, measured 2026-09-10, compiler `73312a7472fd`, tree `5b064fd9d`

```python
# pkg/__init__.py
try:
    import ctypes
    from . import primary as backend
    backend_kind = "primary"
except ImportError:
    from . import fallback as backend
    backend_kind = "fallback"
print(backend_kind, backend.B, backend.name())
```

| compiler | output | |
| --- | --- | --- |
| CPython (guard absent in both) | `fallback 27 fallback` | the oracle |
| pxx `73312a7472fd` | `fallback 99 primary` | **the handler ran and the other module answered** |
| pxx `6d53c745ea69` | `fallback 27 fallback` | fixed |

**The two halves of one seam disagreed.** The runtime string is honest — the
handler DID run — and every member read came off the branch that did not. No
diagnostic, at the exact point in a program where the whole purpose of the code
is to say which backend is live.

# The cause, and it is three things in a row

**1. The alias table is FIRST-WINS.** `FindUnitOrAlias` scans from index 0 and
takes the first row whose name matches. A second registration of the same alias
is appended and never reached. The doc comment on `PyParseFallbackImportTry`
asserted the opposite in its own justification — *"the fallback branch rebinds
the names it needs"* — which is exactly the property that does not hold.

**2. The dead arm registered at all.** Two of the three registration sites carry
`not SoftUnitMissed`. The third is `PyBindImportUnitAlias`, the arm extracted
from three copies for `from . import X as Y` — **the spelling a seam writes.**
A per-site guard could not have covered it anyway: an import standing BEFORE the
failing one in the same run registers with `SoftUnitMissed` still False.

**3. `SoftUnitMissed` accumulated across a whole import RUN.** It describes ONE
import. `PyParseOneImport` has cleared it per statement since `from tkinter
import ttk` lost its alias to an earlier import's miss; `PyParseImportRun` never
did. So in `try: import ctypes; from pkg import fallback as backend` the second
import saw a miss that was not its own, skipped its alias, and bound `backend`
to None as an optional-missing name — and a None **global** shadows a unit alias
at every use, so the handler's correct rebinding lost anyway and the seam
reported `AttributeError: 'NoneType' object has no attribute 'B'`.

**Same defect, two different wrong answers**, and which one you got depended on
whether the spelling was relative or absolute.

# THE FIX MEASURED AS NO CHANGE FIRST, AND THAT IS THE PART WORTH READING

The rollback went into `PyParseFallbackImportTry` and the probe answered exactly
as before. **Two layers resolve imports and the PRESCAN runs first** — the same
two-layer trap `bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved`
recorded in its own commit message a few hours earlier, in this same routine,
against this same walk. It was read, understood, and walked into anyway, because
the rollback *looked* like it belonged next to the hoist rollback that is
already there.

The tell was free and was not taken: a fix that changes nothing has not been
placed where the thing it repairs happens. Both rollbacks are kept — the ticket
above establishes that either alone is insufficient.

# Controls

- **Positive, measured:** the PINNED compiler compiles
  `try: import <missing>; import math as deadonly / except ImportError: ...`
  and prints `fallback 3.141592653589793` — it says the handler ran AND reads
  `pi` off a module only the dead arm bound. CPython raises
  `NameError: name 'deadonly' is not defined`. **Refusing the name is agreement
  with the oracle, not a divergence**; we refuse it earlier, at compile time.
  The pin also fails the main test, but at a DIFFERENT mechanism (it predates
  the `from . import X as Y` alias extraction), so it is a control for the test
  and not for this fix.
- **Must still work:** when the guarded import RESOLVES, the try arm is live and
  ITS alias must win — asserted as the `live-arm` row. Without it the fix reads
  as "the handler always wins", which is a different and wrong rule.
- **Both doors:** the relative `from . import X as Y` (inside the package) and
  the absolute `from pkg import X as Y` (in the main program). The plain
  `import X as Y` site is the Makefile control.
- **Oracle:** the guarded module is a name NEITHER runtime has, so CPython takes
  the same branch and every row is a cross-check rather than a record of our
  divergence.
- **Fifteen named neighbours re-run** against the Makefile's own assertions:
  the three `fallback_import*` rows, the dead-path test, `import_alias`,
  `import_alias_collides`, `from_import_as_alias`, `from_import_as_rename`,
  `a_module_alias_reaches_the_modelled_modules`, both relative-import tests,
  `dotted_package_import`, `import_spellings`, `a_class_through_a_dotted_package`.
  All match.

# What it is worth, stated as a delta and not as a feeling

**Zero modules.** lekkerzeilen's seam returns the module as a VALUE
(`return _pxx, "pxx"`) and walls on
`bug-n-a-module-bound-by-an-import-is-not-a-value`, still at
`platform/__init__.py:95`, unmoved.

Its worth is the trap it removes. `import ... as` is the OTHER standard spelling
of that seam, it is legal CPython that behaves identically there, and it is the
obvious thing to rewrite lekkerzeilen's `__init__.py` into to get past the
module-as-a-value wall — CLAUDE.md permits changing lekkerzeilen where something
is principally incompatible with NilPy, and this looked like the case for it.
**Written that way against `73312a7472fd`, the demo would have silently linked
the ctypes backend into a pxx build that reports itself as the pxx one.** Found
by probing the rewrite before proposing it.

# Not fixed, filed instead

A straight-line rebind of the same alias still answers the FIRST binding where
CPython answers the second — `from . import a as x` then `from . import b as x`
gives `a`. Same table, different question: the NilPy shim substitutions
(`<module> -> mimic_<module>`) live in it too, so last-wins is a change with its
own blast radius and no corpus consumer today.
`bug-n-a-unit-alias-rebind-is-silently-ignored`.

# The test

`test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy` with
the package `test/nilpy_seampkg/`, wired at `Makefile:1276` beside the dead-path
test it extends, plus the printf control for the plain `import X as Y` site.
