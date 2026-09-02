program prog;
uses realunit;
var s: AnsiString;
begin
  s := 'world';
  WriteLn('hello ', s);          { needs the real builtinheap }
  WriteLn(Sqrt(16.0):0:1);       { injects, and needs, the real math }
  WriteLn(Answer);               { and realunit must still come from here }
end.
