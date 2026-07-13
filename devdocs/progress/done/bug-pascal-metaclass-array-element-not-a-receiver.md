---
prio: 55
---

# bug: a metaclass ARRAY ELEMENT is not accepted as a receiver — silent garbage

- **Track:** P (Pascal frontend)
- **Found:** 2026-07-13, while writing b317's regression test (fcl-json corpus). The test
  itself tripped over it, which is how it surfaced.

## Repro (16 lines, verified against FPC)

```pascal
program vc;
{$mode objfpc}{$H+}
type
  TBase = class class function Tag: string; virtual; end;
  TBaseClass = class of TBase;
  TA = class(TBase) class function Tag: string; override; end;
class function TBase.Tag: string; begin Tag := 'base'; end;
class function TA.Tag: string;    begin Tag := 'A'; end;
const
  Map : array[0..0] of TBaseClass = (TA);
var
  c: TBaseClass;
begin
  c := Map[0];
  writeln('via var:  ', c.Tag);      { FPC: A    pxx: A    }
  writeln('via elem: ', Map[0].Tag); { FPC: A    pxx: 4227577  <-- GARBAGE }
end.
```

`Map[0].ClassName` happens to work; `Map[0].Tag` (a virtual class method) returns an
integer-looking value. Assigning the element to a metaclass VARIABLE first and calling
through that is correct — so the value in the array is right; it is the RECEIVER handling
that is wrong.

Silent: no error, no warning, a plausible-looking number.

## Cause

The metaclass-receiver checks in `compiler/parser.inc` (the class-reference-op and
metaclass-call paths, e.g. around the `Syms[ASTIVal[node]].PtrElemTk = tyClass` tests)
only accept:

- `ASTKind[node] = AN_IDENT` — a `class of T` VARIABLE, and
- `ASTKind[node] = AN_PTR_CAST` — an inline metaclass cast.

An `AN_INDEX` (an element of an `array of TSomeClass`) matches neither, falls through, and
the call is built as if the receiver were an ordinary pointer value.

## Fix direction

Generalise the receiver test to any node whose STATIC type is a metaclass, rather than
enumerating AST kinds. The array case needs the element's class id, which the symbol
already carries for an array-of-metaclass (element `tyPointer` with a class element rec).
`ResolveNodeRec`-style resolution is the natural home — the same "which class is this
expression" question the record path already answers, and adding kinds one at a time here
is exactly what left this hole (see also b289, the selector-after-indexed-property fix).

Note b317's regression test deliberately reads the const through `ClassName` and says why,
so it does not depend on this being fixed.

## RESOLVED 2026-07-13 (b328)
Exactly the fix direction above: the metaclass-receiver detection now also
accepts an AN_INDEX over an array symbol whose element is a metaclass (the sym
carries PtrElemTk=tyClass / PtrElemRec — a clean discriminator against arrays
of ordinary record pointers). Virtual class methods, virtual constructors and
the class-ref ops all dispatch through the element now. Pinned:
test/test_metaclass_array_element_b328.pas. fpjson suite stays 203/203.

## Log
- 2026-07-13 — resolved, commit HEAD.
