program test_char_arg_ansistring;

{ Passing a single-char literal ('x', a tyChar) to a routine that expects an
  AnsiString parameter. Under PXX_MANAGED_STRING the literal types as tyChar;
  overload resolution must accept it for an AnsiString param (char marshals to
  a 1-char managed string, mirroring the tyChar -> tyString rule). Previously
  TypesCompatible only allowed tyChar -> tyString, so the arg was rejected and
  the call reported "no overload ... matches these arguments". }

{$define PXX_MANAGED_STRING}

procedure Echo(v: AnsiString);
begin
  writeln(v);
end;

function Tagged(v: AnsiString): AnsiString;
begin
  Tagged := '[' + v + ']';
end;

var c: Char;
begin
  Echo('x');            { single-char literal arg }
  Echo('yy');           { multi-char, regression guard }
  c := 'z';
  Echo(c);              { char variable arg }
  writeln(Tagged('q')); { single-char arg through a function result + concat }
end.
