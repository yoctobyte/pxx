---
track: A
prio: 45
type: bug
blocked-by: []
---

# A fixed-array call result is refused as a `const`/by-ref argument

- **Type:** bug (spurious refusal) — **Track A**
- **Found:** 2026-08-11, while verifying
  [[bug-a-fixed-array-function-result-faults-on-i386-and-arm32]]. The array arm
  is the only aggregate that refuses; the record and string arms already
  materialise a temp.

```pascal
{$mode objfpc}
type TArr = array[0..2] of Integer;
     TR   = record x, y: Integer; end;
function MkArr: TArr;  begin MkArr[0]:=1; MkArr[1]:=2; MkArr[2]:=3; end;
function MkR:   TR;    begin MkR.x:=4; MkR.y:=5; end;
function MkS:   string; begin MkS := 'abcd'; end;
function SumA(const a: TArr): Integer;  begin SumA := a[0]+a[1]+a[2]; end;
function SumR(const r: TR): Integer;    begin SumR := r.x+r.y; end;
function Twice(const s: string): Integer; begin Twice := Length(s)*2; end;
begin
  WriteLn(SumR(MkR));    { pxx 9  = FPC 9  }
  WriteLn(Twice(MkS));   { pxx 8  = FPC 8  }
  WriteLn(SumA(MkArr));  { FPC 6; pxx REFUSES }
end.
```

```
pascal26: error: by-reference argument must be a variable
```

FPC prints `9 8 6`.

## Where to start (not yet diagnosed)

`bug-const-byref-record-param-temp` (done) is the record half of exactly this:
a call result passed to a `const` record parameter materialises into a caller
temp whose address is passed. The array arm of the by-ref argument check never
learned the same trick, so it still demands an lvalue.

`ProcRetFixedArrBytes` + `ABIRetViaHiddenDestProc` already give the caller a
right-sized scratch for `a := MkArr` on all five targets (verified 2026-08-11),
so the temp this needs is the one the assignment path already allocates — the
missing piece is likely only the argument-side lvalue check and routing the
hidden destination at a call ARGUMENT rather than an assignment RHS.

Sibling worth checking in the same pass: a `var` (not `const`) parameter must
keep refusing a call result — FPC refuses that too, so the fix must not widen
the check for both.

## Gate

The program above matching `fpc -O1` on x86-64 and all four cross targets;
a `var`-parameter call-result argument still refused; self-host byte-identical.
