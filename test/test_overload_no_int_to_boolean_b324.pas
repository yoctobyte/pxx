{ An INTEGER argument must not overload-match a Boolean parameter (b324).

  TypesCompatible's blanket ordinal-ordinal rule let a NativeInt argument map
  onto `Make(Data: Boolean)` — declared before the Integer overload — so
  fpjson's TJSONArray.Create([1,2,3]) built [true, true, true]: silent wrong
  VALUES. FPC has no implicit integer->Boolean conversion. A Boolean parameter
  now accepts only a Boolean argument; the reverse direction is unchanged. }
program test_overload_no_int_to_boolean_b324;
{$mode objfpc}{$h+}

function Make(B: Boolean): String;
begin
  Result := 'bool';
end;

function Make(I: Integer): String;
begin
  Result := 'int';
end;

var
  N: NativeInt;
  W: Word;
begin
  N := 3;
  W := 7;
  Writeln('n=', Make(N));      { no NativeInt overload: must pick Integer, never Boolean }
  Writeln('w=', Make(W));
  Writeln('b=', Make(True));
  Writeln('i=', Make(5));
end.
