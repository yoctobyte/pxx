---
slug: bug-p-a-nested-class-method-called-from-inside-its-generic-outer-is-unresolved
track: P
prio: 60
type: bug
status: backlog
owner:
blocked-by: []
summary: "Calling a method of a NESTED class from inside a method body of the enclosing GENERIC class fails with `unresolved forward: TInner.GetIt`. 20-line repro, FPC 3.2.2 prints 9. The boundary is the CALL SITE, not the declaration: declaring the nested method and never calling it compiles; calling it from OUTSIDE the generic class compiles; calling it from inside one of the outer's own method bodies does not. A non-generic outer is unaffected. Found while localising the rung-6b rtl-generics wall (feature-pascal-corpus-expansion), where TStack<T> is the instance -- it returns and consumes its inherited nested TEnumerator. Binary 414252435fb1 at 05d8f21db."
---

# A nested class's method, called from inside its GENERIC outer, is unresolved

## Repro (20 lines, FPC-verified)

```pascal
unit u; {$mode objfpc}
interface
type
  generic TOuter<T> = class
  public type
    TInner = class
      F: Integer;
      function GetIt: Integer;
    end;
    function Make: TInner;
    function Probe: Integer;
  end;
implementation
function TOuter.TInner.GetIt: Integer;
begin Result := 9; end;
function TOuter.Make: TInner;
begin Result := TInner.Create; end;
function TOuter.Probe: Integer;
begin Result := Make.GetIt; end;     { <-- the call site that breaks it }
end.
```

Driver: `type TO2 = specialize TOuter<Integer>; ... writeln(o.Probe)`.

```
pxx (414252435fb1)  pascal26:2: error: unresolved forward: TInner.GetIt
FPC 3.2.2           9
```

The reported position is useless again — `pascal26:2` with an `in:`/`near:` in
`compiler/builtin/builtinheap.pas`. Reduce from the SHAPE, not the coordinate.

## The boundary is the CALL SITE, not the declaration

Measured, same binary, each a separate unit:

| shape | result |
| --- | --- |
| nested method declared + implemented, **never called** | **ok** |
| nested method called from **outside** the generic class (`o.Make.M1` in the driver) | **ok** |
| nested method called from **inside** an outer method body (`Make.GetIt`) | **`unresolved forward`** |
| same call, outer class **not generic** | **ok** |

So the implementation IS parsed and registered — three functions on a nested
class resolve fine when the calls come from the driver. It is the call from
within the generic body, which goes through specialization, that fails to find
it. `function` vs `procedure` vs `constructor` makes no difference; all three
were tried and all three fail at that call site.

## Why it matters now

This is the shape at `generics.collections.pas:2129` —
`function TStack<T>.GetEnumerator: TEnumerator`, where `TEnumerator` is the
nested enumerator inherited from `TCustomList<T>` and used by the class's own
bodies. It is the wall revealed once rung 6b's `end`-imbalance is padded over;
see [[feature-pascal-corpus-expansion]]'s canonical table for the measurement
chain and the binary provenance.

**Not proven to be the same defect as the `end`-imbalance** that the truncation
bisect is chasing there — that one originates at or below line 1815 and this
site is at 2129. Two findings, one unit, and the relationship is open.
