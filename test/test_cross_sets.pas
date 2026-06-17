program test_cross_sets;
type
  TDay = (Mon,Tue,Wed,Thu,Fri,Sat,Sun);
  TDays = set of TDay;
  TBS = set of Byte;
var s: TDays; a, b: TBS;
begin
  s := [Mon, Wed, Fri];
  if Wed in s then writeln('wed yes') else writeln('wed no');
  if Tue in s then writeln('tue yes') else writeln('tue no');
  s := s + [Tue];
  if Tue in s then writeln('tue now yes') else writeln('tue now no');
  a := [1,2,3];
  b := [1,2,3,4];
  if a <= b then writeln('subset') else writeln('not');
  if b <= a then writeln('rsubset') else writeln('not2');
  if a = b then writeln('eq') else writeln('neq');
  a := a * b;
  if 3 in a then writeln('inter ok') else writeln('inter bad');
  a := b - [4];
  if 4 in a then writeln('diff bad') else writeln('diff ok');
end.
