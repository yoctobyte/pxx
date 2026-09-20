---
slug: feature-n-dataclasses-replace-and-copy-copy-need-one-capability-per-object-field-enumeration
title: dataclasses.replace and copy.copy of an object are ONE missing capability — per-object field enumeration at run time
track: N
type: feature
prio: 45
status: backlog
owner: ""
created: 2026-09-20
found-by: frankH
tags: [nilpy, dataclasses, copy, rtti, introspection]
blocked-by: []
summary: "MECHANISM: `dataclasses.replace(obj, **changes)` returns a NEW instance of obj's class with the named fields replaced, so it needs (a) the ability to make an instance of a class known only at run time and (b) the ability to enumerate that instance's fields in order. NilPy has NEITHER, and the same two are what `copy.copy` of an arbitrary object needs -- mimic_copy.py already refuses it in those words ('copying an arbitrary object needs __copy__ / __reduce_ex__ introspection that NilPy does not have'). So these are ONE capability wearing two module names, and implementing either separately would build half of it twice. WHAT IS NOT MISSING, measured, and it is what makes this look easier than it is: the dynamic ATTRIBUTE GET already works on a variant-held instance -- `sol.name` reads correctly -- so a per-object field table exists for lookup BY NAME. It is ENUMERATION and ALLOCATION that are absent. A PARSE-TIME DESUGAR IS NOT A FIX FOR THE REAL PROGRAM, and this is the measurement to keep: the obvious implementation builds a constructor call from the statically known class, and BOTH real call sites (tuxspaceprogram/shape.py:115 and :135) take their receiver out of a dict value inside a comprehension, where the class is a variant -- `self.by_part` is a TPyDict and the element class is not carried. A fixture with a statically typed receiver would pass while the program that motivated the work still walls."
---

# replace() and copy() of an object are one capability

Found 2026-09-20 (frankH) censusing That Space Program under NilPy.

`dataclasses.replace` walls two TSP files, and they are **one site**, not two:
both report `pascal26:115`, and `bpedit.py`'s own line 115 is a docstring —
the diagnostic is printing shape.py's line number with no file name. The site is
`shape.py:115`, with a second at `shape.py:135`.

## Why the cheap implementation does not reach it

The obvious desugar is parse-time: with the receiver's class known, build
`Cls(f0, f1, ...)` taking each argument from the keyword if given and from
`recv.fi` otherwise. Measured, that does not fix either real call site:

```python
self.by_part[iid + suffix] = [
    dataclasses.replace(sol, sweep=sweep, cap_top=False, cap_bottom=False)
    for sol in full]                      # full = self.by_part[iid]
```

`self.by_part` types as a TPyDict (`PXXDBG=n.flddecl` says `tk=6 rec=53`) and
the element class is not carried through the dict, so `sol` is a variant. Both
sites have this shape. **A fixture with a statically typed receiver would pass
while shape.py still walls** — the reduction would fix an axis the real program
does not have.

## What is actually missing, and what is not

Not missing: attribute lookup BY NAME on a variant-held instance. Measured —
`sol.name` on a dataclass instance pulled out of a dict of lists prints
correctly, so per-object field metadata exists for lookup.

Missing: **enumerating** an instance's fields, and **allocating** an instance of
a class known only at run time. `copy.copy` needs exactly the same two, and
`lib/rtl/mimic_copy.py` already says so in its own refusal — which is worth
reading before designing this, because it also states the reason a partial
implementation is worse than none: returning the object unchanged would silently
share the state the caller asked to copy.

## Note on semantics, so a later implementation does not get it subtly wrong

CPython's `replace()` calls the class's `__init__`, so `__post_init__` runs and
`init=False` fields are rejected. A clone-and-set implementation skips both.
That difference is invisible on a plain dataclass and visible the moment one has
`__post_init__`, so it belongs in the design rather than in a later bug report.
