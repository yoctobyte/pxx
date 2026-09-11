unit unit_a_second_lowering_error_in_a_unit;
{ A SECOND lowering check inside a `uses`d unit, so the `in:` pair beside this
  fixture is not one call site passing for a fix.

  CHOSEN BY MEASURING THE PRE-FIX BINARY, not by picking a different-looking
  error. Five candidate classes were run against it: record ordering (`<` on two
  records) and an undefined `goto` label ALREADY printed `in:` before the fix,
  so a row built on either could never have failed. The element-count form of
  Initialize/Finalize did not -- it is ir.inc's own lowering arm and it reaches
  ErrorAtRecover with a node and nothing else, exactly like the assignment check
  the sibling fixture exercises.

  The line number is deliberately NOT pinned by the Makefile row; the assertion
  is the PATH, so this file may grow freely. }
interface

procedure Go;

implementation

procedure Go;
var
  a: array[0..3] of Integer;
begin
  a[0] := 0;
  Initialize(a, 4);
end;

end.
