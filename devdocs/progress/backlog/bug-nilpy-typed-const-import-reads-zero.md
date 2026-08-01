---
track: N
prio: 60
type: bug
blocked-by: []
---

# Nil Python importing a Pascal *typed* constant reads zero, not the initializer

A `.npy`/`.py` file importing a typed constant (`const Name: T = value;`) from a
Pascal unit gets the zero value of `T` instead of the declared one. Untyped
constants are fine, and **Pascal reading the same unit is fine** — so this is
the Nil Python import path, not the unit or the constant itself.

Silent: no warning, no error, just a wrong value. Found while documenting the
shims (Track D), not by a failing test.

## Repro

`u/myconst2.pas`:

```pascal
unit myconst2;
interface
const
  Untyped = 2.5;
  TypedConst: Double = 2.5;
  TypedInt: Integer = 7;
implementation
end.
```

`k2.npy`:

```python
from myconst2 import Untyped, TypedConst, TypedInt
print(Untyped)
print(TypedConst)
print(TypedInt)
```

```
$ ./pascal26 -Fuu k2.npy k2 && ./k2
2.5      <- correct (untyped const)
0.0      <- WRONG, expected 2.5
0        <- WRONG, expected 7
```

The same unit read from Pascal prints both correctly:

```pascal
program pk;
uses myconst2;
begin
  writeln(TypedConst:0:2);   { 2.50 — correct }
end.
```

Verified against `stable_linux_amd64/default/pinned` at
`a03d51f1c` (docs-only commit; the binary is the pinned one, unchanged by it).

## Why it matters beyond a toy

`lib/pcl/mimic_reportlab_lib_units.pas` declares its units this way — precisely
because a const *expression* would be folded by the integer evaluator, so the
values are written out as typed constants:

```pascal
const
  inch: Double = 72.0;
  cm: Double = 28.346456692913385;
  mm: Double = 2.834645669291339;
```

So the shipped shim currently hands `0.0` to any program doing

```python
from reportlab.lib.units import mm
```

and every measurement derived from it silently becomes zero — a PDF laid out
entirely at the origin, with no diagnostic anywhere. `mimic_reportlab_lib_
pagesizes` and the other `Double`-valued shims are worth checking for the same
exposure once this is fixed.

## Notes

Affects at least `Double` and `Integer`, so it reads like the initializer is
simply not carried across the Nil Python import rather than a type-specific
conversion fault. The untyped-const path working suggests the two are resolved
by different mechanisms — the untyped one likely inlined as a literal at the use
site, the typed one referenced as storage whose initializer never lands.

Not routed around anywhere: the shim keeps its platonic declaration, and the
docs written alongside this ticket do not use `mm` in an example.
