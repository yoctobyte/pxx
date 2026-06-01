program test_writeln_mix;
var
  g: AnsiString;
procedure Test(l: Integer);
begin
  writeln('literal1 ', g, ' literal2 ', l);
end;
begin
  g := 'global';
  Test(42);
end.
