program test_cross_set_subrange;
{ Sets over an integer subrange (set of 1..N): union/intersection/difference and
  membership. `set of <subrange>` used to mistype the variable (not tySet) so set
  ops read garbage / crashed. x86-64 (set codegen is x86-64-only on cross backends). }
var s1, s2, su, si, sd: set of 1..20; i: Integer;
begin
  s1 := [1, 2, 3, 4, 10, 15];
  s2 := [3, 4, 5, 6, 15, 20];
  su := s1 + s2;
  si := s1 * s2;
  sd := s1 - s2;
  write('union:'); for i := 1 to 20 do if i in su then write(' ', i); writeln;
  write('inter:'); for i := 1 to 20 do if i in si then write(' ', i); writeln;
  write('diff:'); for i := 1 to 20 do if i in sd then write(' ', i); writeln;
  if 15 in si then writeln('15in') else writeln('15out');
end.
