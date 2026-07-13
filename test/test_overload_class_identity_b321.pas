{ Method overloads distinguished only by CLASS IDENTITY (b321).

  Two defects, both silent:

  1. The class-method DECL registration was rec-blind (FindProcOverload, no
     ProcParamRecId stored), so `Add(Item: TBase)` and `Add(D: TDer)` — same
     arity, both params tyClass — shared ONE proc slot and each IMPL body
     clobbered the other's. fpjson's `Add(TJSONData(AnObject))` inside
     `Add(AnObject: TJSONObject)` then re-dispatched to ITSELF and recursed to
     stack overflow.

  2. Overload RANKING tied all tyClass candidates at rank 0, so first-declared
     won regardless of the argument's class. FPC picks the EXACT class, accepts
     an ancestor up-cast as merely compatible, rejects an unrelated class.

  Verified against FPC: B.Add(D) runs Add(TDer); the TBase(D) cast inside runs
  Add(TBase); Add(B2) with an unrelated sibling runs Add(TBase) via up-cast...
  (TOther unrelated to TBase would be a compile error in FPC; not pinned here). }
program test_overload_class_identity_b321;
{$mode objfpc}{$h+}

type
  TBase = class end;
  TDer = class(TBase) end;
  TBox = class
    function Add(Item: TBase): Integer;
    function Add(I: Integer): Integer;
    function Add(D: TDer): Integer;
  end;

function TBox.Add(Item: TBase): Integer;
begin
  Writeln('Add(TBase)');
  Result := 1;
end;

function TBox.Add(I: Integer): Integer;
begin
  Writeln('Add(Integer)');
  Result := 2;
end;

function TBox.Add(D: TDer): Integer;
begin
  Writeln('Add(TDer)');
  Result := Add(TBase(D));   { the cast DEMOTES: must bind Add(TBase), not recurse }
end;

var
  B: TBox;
  D: TDer;
  P: TBase;
begin
  B := TBox.Create;
  D := TDer.Create;
  B.Add(D);          { exact: Add(TDer), whose body then runs Add(TBase) }
  P := TBase.Create;
  B.Add(P);          { exact: Add(TBase) }
  B.Add(5);          { Add(Integer) }
end.
