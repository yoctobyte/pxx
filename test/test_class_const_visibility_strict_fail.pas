program test_class_const_visibility_strict_fail;
{ Under --strict-visibility a strict-private class const reached from a
  DESCENDANT method must be rejected (bug-pascal-class-const-visibility,
  the tclass12b shape). Compiles fine in the lax default; only --strict-
  visibility bites. }

type
  TBase = class
  strict private const Secret = 5;
  end;

  TDer = class(TBase)
  public
    function Peek: Integer;
  end;

function TDer.Peek: Integer;
begin
  Result := Secret;   { strict private in the ancestor — illegal from here }
end;

var d: TDer;
begin
  d := TDer.Create;
  writeln(d.Peek);
end.
