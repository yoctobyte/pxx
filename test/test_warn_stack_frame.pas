program test_warn_stack_frame;
{ A routine with a >1MB stack local trips the oversized-stack-frame warning
  (feature-warn-oversized-stack-frame). The program still compiles and runs
  correctly — the warning is non-fatal unless -Werror promotes it. A small
  frame, or --max-stack-frame=0, stays silent. }

procedure BigLocal;
var buf: array[0..2097151] of Byte;   { 2 MB > the 1 MB default threshold }
begin
  buf[0] := 7;
  buf[2097151] := 35;
  writeln(buf[0] + buf[2097151]);     { 42 }
end;

procedure SmallLocal;
var buf: array[0..255] of Byte;        { 256 B — well under threshold, silent }
begin
  buf[0] := 1;
  writeln(buf[0]);                      { 1 }
end;

begin
  SmallLocal;
  BigLocal;
end.
