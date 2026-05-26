program test_heap;
var
  p1, p2, p3: LongWord;
begin
  p1 := GetMem(16);
  p2 := GetMem(32);
  p3 := GetMem(8);
  
  if p1 <> 0 then writeln(1) else writeln(0);
  if p2 > p1 then writeln(1) else writeln(0);
  if p3 > p2 then writeln(1) else writeln(0);
  if (p1 and 7) = 0 then writeln(1) else writeln(0);
  if (p2 and 7) = 0 then writeln(1) else writeln(0);
  if (p3 and 7) = 0 then writeln(1) else writeln(0);
end.
