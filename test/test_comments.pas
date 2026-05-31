{$NESTEDCOMMENTS ON}
{$CSTYLECOMMENTS ON}
program test_comments;
{ Comment-handling regression:
  - (* *) followed by code on the same line (A3, unconditional fix)
  - nested { } under NESTEDCOMMENTS
  - nested (* *) under NESTEDCOMMENTS
  - /* */ C-style under CSTYLECOMMENTS }
var x: Integer;
begin
  { outer { inner } still in outer comment } x := 1;
  (* outer (* inner *) still in outer *) x := x + 1;
  x := x /* c-style between tokens */ + 1;
  writeln(x); (* trailing comment then nothing *)
  writeln('done'); (* same-line *) { brace same-line }
end.
