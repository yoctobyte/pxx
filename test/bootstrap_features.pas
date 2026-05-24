program BootstrapFeatures;
const
  A = 64;
  B = 56;
  C = A + B;
var
  s: AnsiString;
  i: Integer;
begin
  s := 'abc';
  i := 2;
  writeln(C);
  writeln(Ord(s[i]));
  case s[1] of
    'a', #98: writeln('case-ok');
    else writeln('case-bad');
  end;
  writeln(ParamCount);
end.
