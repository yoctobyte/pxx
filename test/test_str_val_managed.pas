program test_str_val_managed;
{ Str/Val with a managed AnsiString source/destination. Str's frozen result
  assigns into a managed AnsiString; Val now accepts an AnsiString source (param
  widened to AnsiString, so a frozen source coerces and a managed one passes
  through). Run in managed mode (-dPXX_MANAGED_STRING) where `AnsiString` is the
  refcounted managed kind. }
var
  s: AnsiString;
  x, c: Integer;
  f: Double;
begin
  x := 42;
  Str(x, s);
  writeln('[' + s + ']');         { Str -> managed dest }
  Val(s, x, c);                   { Val <- managed source }
  writeln(x, ' code=', c);
  s := '3.5';
  ValFloat(s, f, c);
  writeln(f:0:1, ' code=', c);
  s := '9z';
  Val(s, x, c);
  writeln(x, ' code=', c);        { FPC convention: code = 1-based bad-char pos }
end.
