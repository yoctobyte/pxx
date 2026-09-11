---
slug: bug-n-a-guarded-import-inside-a-module-makes-its-importer-bind-every-name-to-none
title: "A package whose own guarded import misses made its importer bind every from-imported name to None, silently"
track: N
type: bug
prio: 85
status: done
created: 2026-09-11
found: 2026-09-11
found-by: frankZ
owner: frankZ
tags: [nilpy, imports, silent-wrong-value]
blocked-by: []
summary: "FIXED 2026-09-11, and it was PRESENT IN PIN 095ef4811a5b and every binary before it. `SoftUnitMissed` is a global. A module that RESOLVED could set it during its own compile -- one `try: from <absent> import X / except ImportError:` anywhere in the module is enough -- and the flag came back out of ParseUsesUnit, where the importing from-import read it as ITS OWN miss and bound every name it was importing to None as an optional-missing name. `from pkg import VALUE` gave None for a plain `VALUE = 27`. NO DIAGNOSTIC: a variant global is born VT_EMPTY, which IS None, so the program compiles, runs, and prints a wrong value far from its cause -- and the guarded-import idiom that triggers it is exactly what a portable package writes. Fixed at PyParseImportUnitAs: clear the flag before resolving and, when the unit was actually COMPILED (CompiledUnitCount went up), clear whatever the nested compile left. ParseUsesUnit sets the flag in exactly one place and restores CompiledUnitCount on that path, so a genuine miss and a nested one are distinguishable by the count."
---

# The repro, four lines of package and two of program

```python
# pkg/__init__.py
VALUE = 27

try:
    from definitely_no_such_module import Image
    have = True
except ImportError:
    have = False
```

```python
from pkg import VALUE
print("v", VALUE)      # CPython: v 27      pxx: v None
```

# Why it is the expensive shape

Not a crash and not a diagnostic. `VALUE` is a plain integer constant; it comes
back as `None` because the importer decided the module was unavailable. The
module is right there and every other thing about it works — `who()` called
fine in the probe. The trigger is a construct the module wrote about ITSELF, so
nothing at the use site or in the importer's own source hints at it.

# How it was found, and it is the rule finding itself

Adding a PRESENCE control. The fix in
[[bug-n-a-dead-guarded-import-arm-still-compiles-the-module-it-imports]] works by
NOT binding a name, and an absence cannot be its own evidence — so the fixture
needed a row where the None binding must still happen. Giving the test package a
guarded import of its own is what made this fire. **No fixture in the suite had
a package that guards an import**, which is why a bug this loud in effect stayed
invisible: the corpus had the construct, the tests did not.

# The fix

`PyParseImportUnitAs` clears `SoftUnitMissed` before `ParseUsesUnit` and clears
it again afterwards when `CompiledUnitCount` went UP — i.e. when a unit was
actually compiled, so anything the flag now says was said by that unit's own
imports. A genuine miss restores the count (pasparser_proc.inc's
empty-`UnitContent` arm under `SoftUnitResolve`) and is therefore distinguishable
without a second flag. An already-compiled unit exits early, writes nothing, and
correctly leaves the flag clear.

`PyParseOneImport` already clears the flag per STATEMENT for the same class one
level out — an earlier import's miss leaking into a later one, which cost
`from tkinter import ttk` its binding. That clear cannot reach this case,
because here the contaminating write happens DURING our own resolution.

# Note

Inert for `$(PXX_STABLE)` consumers until a pin carries it, and `make pin` is
owner-only.
