program test_cross_shortcircuit;
{ Short-circuit and/or (FPC short-circuit default): the right operand runs only when the
  left does not already decide the result. A counter proves which sides ran; a
  nil-guard proves the faulting right operand is skipped. Bitwise integer and/or
  stay full-width. Output must be byte-identical on every target. }
var calls: Integer;
function Tick(v: Boolean): Boolean;
begin calls := calls + 1; Tick := v; end;
var p: ^Integer;
begin
  calls := 0;
  if False and Tick(True) then writeln('x');
  writeln('and-false calls=', calls);
  if True or Tick(True) then writeln('or-true');
  writeln('or-true calls=', calls);
  if True and Tick(True) then writeln('and-true');
  writeln('and-true calls=', calls);
  if False or Tick(True) then writeln('or-false');
  writeln('or-false calls=', calls);
  { combined guard: nil pointer, right side would deref }
  p := nil;
  if (p <> nil) and (p^ = 0) then writeln('deref') else writeln('guard1 ok');
  { chained: only as many evals as needed }
  calls := 0;
  if Tick(True) and Tick(False) and Tick(True) then writeln('y');
  writeln('chain calls=', calls);
  { bitwise integer and/or unaffected }
  writeln('bits ', 6 and 3, ' ', 6 or 1, ' ', 12 and 10);
end.
