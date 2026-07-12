program test_writeln_shortstring_param;
{ writeln of a ShortString/frozen PARAM read the slot as an inline string
  (wild-memory dump); the param slot holds the caller's string ADDRESS
  (bug-pascal-writeln-shortstring-param). }
procedure Check(const S: ShortString);
begin
  writeln('got=', S, ' len=', Length(S));
end;
procedure CheckManaged(const S: ShortString);
begin
  writeln('m=', S);
end;
var f: ShortString; m: AnsiString;
begin
  f := 'HELLO';
  Check(f);
  m := 'WORLD';
  CheckManaged(m);   { managed arg -> frozen param conversion temp }
end.
