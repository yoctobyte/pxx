---
track: N
prio: 75
type: bug
blocked-by: []
---

# Typed-constant initializers are not applied in a Nil Python build

A typed constant (`const Name: T = value;`) in a Pascal unit reads as the zero
value of `T` whenever the **main program is Nil Python** — regardless of who
reads it. Untyped constants are fine. The same unit under a Pascal main is
fine.

Silent: no warning, no error, just a wrong value. Found while documenting the
shims (Track D), not by a failing test.

**This is not an import-boundary bug.** The first read of this ticket said it
was — that was wrong, and the corrected scope is much wider. Pascal code *inside
the unit* reading its own typed constant also gets zero, so any Pascal library
that relies on one misbehaves under a NilPy main even when NilPy never touches
the constant itself. The decisive experiment is below.

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

## The decisive experiment: same unit, same accessor, two mains

The constant is never named by the Nil Python side here — a Pascal function in
the unit reads it, and only the main program's language differs.

`u/rec.pas`:

```pascal
unit rec;
interface
type
  TPt = record x, y: Double; end;
const
  Origin: TPt = (x: 1.5; y: 2.5);
function GetX: Double;
implementation
function GetX: Double; begin GetX := Origin.x; end;
end.
```

```python
from rec import GetX
print(GetX())          # 0.0   <- WRONG
```

```pascal
program rp;
uses rec;
begin
  writeln(GetX:0:2);   { 1.50  <- correct }
end.
```

So the initializer is not being emitted or not being applied for a NilPy main,
rather than being lost in translation on the way across an import.

## Blast radius

Affects `Double`, `Integer` and record-typed constants — consistent with "the
initializer never lands" rather than a type-specific conversion fault. Untyped
constants work, which fits them being inlined as literals at the use site while
a typed constant is storage that someone must initialize.

Every typed constant reachable from a NilPy build is exposed. In-tree today:

| unit | typed constants | why it matters |
| --- | --- | --- |
| `lib/pcl/mimic_reportlab_lib_units.pas` | `inch`, `cm`, `mm`, `pica` | every reportlab measurement becomes 0.0 |
| `lib/rtl/ucomplex.pas` | `i`, `_0` | the imaginary unit reads as 0 — complex math silently wrong |
| `lib/rtl/palparallel.pas` | `ParDefault`, `ParBalanced`, `ParPolite` | parallel policy presets silently become all-zero records |
| `lib/rtl/dynlibs.pas` | `NilHandle` | harmless — its value *is* 0 |

`ucomplex` is the one to look at after `reportlab`: a zeroed imaginary unit
produces plausible numbers that are wrong, with nothing to catch it.

Not routed around anywhere: the shim keeps its platonic declaration, and the
docs written alongside this ticket do not use `mm` in an example.
