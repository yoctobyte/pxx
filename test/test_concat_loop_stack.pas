program test_concat_loop_stack;
{$mode objfpc}{$H+}
{ Literal/char string concatenation in a loop must not consume stack
  (bug-frozen-concat-stack-carve-loop-overflow): the frozen concat codegen
  carves a 272-byte result buffer off the stack with no restore, so
  `s := 'p' + Chr(i)` in a loop overflowed the 8MB stack after ~30k
  iterations. Under the managed default the parser now types literal/char
  concat tyAnsiString (heap path, no carve); the frozen self-build keeps the
  old typing. 200k iterations here = would need ~54MB of stack if the carve
  came back. }
var
  s: AnsiString;
  i, bad: Integer;
  r: record Name: AnsiString; k: Integer; end;
begin
  bad := 0;
  for i := 1 to 200000 do
  begin
    s := 'p' + Chr(65 + (i mod 26));
    if Length(s) <> 2 then Inc(bad);
    r.Name := 'ab' + Chr(48 + (i mod 10)) + 'z';   { chained concat into a field }
    if (Length(r.Name) <> 4) or (r.Name[4] <> 'z') then Inc(bad);
  end;
  writeln(s);              { last: 'p' + Chr(65 + 200000 mod 26) = pW }
  writeln(r.Name);
  writeln('bad=', bad);
end.
