program test_object_reference_error;

{ Member access on a bare `object` reference must be a compile error —
  the reference carries no class; cast to a concrete class first. }

type
  TA = class
    FX: Integer;
  end;

var
  o: object;
  a: TA;
begin
  a := TA.Create;
  o := a;
  o.FX := 3;   { compile error }
end.
