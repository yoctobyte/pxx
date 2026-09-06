---
slug: bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults
track: P
type: bug
prio: 55
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "Passing a named dynamic array through an interface-dispatched call compiles clean and segfaults"
summary: "MEASURED 2026-09-06 at d754eeef1 against fpc 3.2.2 -Mobjfpc. No default values anywhere. `IFoo.A(const a: TArr)` where `TArr = array of Integer`: `i.A(nil)` through the interface reference compiles clean and SEGFAULTS, while `f.A(nil)` on the same object through the CLASS reference prints `A 0`, and `i.B(2)` with a scalar parameter through the SAME interface reference prints `B 2`. fpc prints `A 0` for all three. The two controls are in one file and run in sequence, so the crash is isolated to the pair (interface dispatch, dynamic-array parameter) -- neither half alone. Found while closing bug-p-a-default-value-is-accepted-on-an-open-array-parameter, whose positive control declares an interface method but dispatches through the class because of this. Lane may be A if the cause is in the IMT thunk's argument marshalling; I did not locate it."
---

# A named dynamic array passed through an interface segfaults

```pascal
{$mode objfpc}{$H+}
type
  TArr = array of Integer;
  IFoo = interface
    ['{5E1B0A11-1111-4222-8333-444455556666}']
    procedure A(const a: TArr);
    procedure B(n: Integer);
  end;
  TFoo = class(TInterfacedObject, IFoo) ... end;
var i: IFoo; f: TFoo;
begin
  f := TFoo.Create;
  f.A(nil); f.B(1);      { A 0 / B 1     -- class dispatch, both fine }
  i := f;
  i.B(2);                { B 2           -- interface dispatch, scalar, fine }
  i.A(nil);              { <- segfault   -- fpc prints A 0 }
end.
```

**Two controls, one file, run in order**, which is what makes this a pair and
not two guesses: class dispatch with the dynamic array works, and interface
dispatch with a scalar works, so neither half alone is the defect. No default
values are involved anywhere — this was isolated out of a default-value
investigation and the defaults were removed to get here.

## Done when

`i.A(nil)` prints `A 0`, with a non-empty array asserted as well as `nil` (a
`nil` handle and a mis-marshalled one can both read as length 0 in a callee that
only asks `Length`), and the two controls above kept in the same file.

## The sibling, and what "no shared cause" does and does not mean

[[bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults]] was found in the same sitting, in the same subsystem, at the same
priority. **Read that pairing carefully, because the honest statement is weaker
than either "they are the same bug" or "they are independent."**

What was measured is that each crashes under its own trigger with the other's
trigger controlled out: this one with a scalar parameter and no array anywhere,
that one with no default value anywhere. Neither is a special case of the other's
repro.

What was NOT measured is whether one cause explains both. I did not locate
either. Two crashes in one dispatch mechanism have every reason to share a
cause, and a reader who fixes one should expect the other to fall out and check
rather than assume it will not — **the pair being listed here is not evidence
that they are two.** If they turn out to be one, close this and say so; that is
a better outcome than two tickets held apart by a sentence nobody measured.
