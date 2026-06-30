program test_for_var_inline;
{ Delphi 10.3 Rio inline loop variable: `for var i := a to b` declares a fresh
  Integer counter (no separate `var i:`). Counted form only in v1; for-in inline
  (`for var x in c`) is filed (feature-inline-loop-var-rio). }
var t, s: Integer;
begin
  t := 0;
  for var i := 0 to 4 do t := t + i;          { 0+1+2+3+4 }
  writeln(t);                                  { 10 }

  s := 0;
  for var i := 3 downto 1 do
    for var j := 1 to i do s := s + 1;          { 3+2+1 }
  writeln(s);                                  { 6 }
end.
