program test_overload_class_identity;
{ Overload resolution must consider the argument's CLASS IDENTITY, not just its
  arity. It took the first arity match and bound an UNRELATED class to any
  class-typed parameter, so the callee read one object's memory through another
  class's shape — silent wrong dispatch where the layouts agree, a segfault
  where they do not (bug-a-overload-resolution-ignores-class-identity).

  Descendants must still widen to an ancestor-typed parameter, and a TObject
  parameter must still accept anything: those are valid, and a fix that only
  compared identity exactly would reject working code across every track. }
type
  TA = class
    x: Integer;
  end;
  TB = class
    y, z: Integer;
  end;
  TDerived = class(TA)
    w: Integer;
  end;

function pick(a: TA): Integer; overload;
begin pick := 1; end;
function pick(b: TB): Integer; overload;
begin pick := 2; end;

function anyobj(o: TObject): Integer; overload;
begin anyobj := 9; end;

var a: TA; b: TB; d: TDerived;
begin
  a := TA.Create;
  b := TB.Create;
  d := TDerived.Create;
  WriteLn(pick(a));       { 1 — exact }
  WriteLn(pick(b));       { 2 — was 1: unrelated class bound to the TA param }
  WriteLn(pick(d));       { 1 — descendant widens to its ancestor's param }
  WriteLn(anyobj(a));     { 9 — TObject param accepts anything }
  WriteLn(anyobj(b));     { 9 }
end.
