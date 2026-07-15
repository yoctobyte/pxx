program strict_fpc_case_fail;
{ Negative: --strict-fpc turns on StrictCase, so a duplicate case label is an
  error. Compiles fine in the lax default; only --strict-fpc (or --strict-case)
  rejects it. Proves the umbrella actually activates its member flags.
  feature-strict-fpc-umbrella. }
var x, y: Integer;
begin
  x := 1;
  case x of
    1: y := 10;
    1: y := 20;   { duplicate label — StrictCase rejects }
  end;
  writeln(y);
end.
