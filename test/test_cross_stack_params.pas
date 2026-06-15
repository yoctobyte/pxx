program test_cross_stack_params;

{ Regression for the ARM32 self-host wall: routines with more than 4 parameters
  pass the 5th+ argument on the stack. The caller left a register arg (not the
  stack arg) at [sp] before the call, and the callee read stack arg i at a
  reversed offset, so a stack-passed open-array param's pointer came back as a
  scalar arg (e.g. 1) and indexing it segfaulted in RegisterProc. Verifies both
  plain scalar overflow args and a stack-passed `array of AnsiString`. }

var Out: array[0..7] of AnsiString;

function Six(a, b, c, d, e, f: Integer): Integer;
begin
  Six := a * 100000 + b * 10000 + c * 1000 + d * 100 + e * 10 + f;
end;

function Seven(a, b, c, d, e, f, g: Integer): Integer;
begin
  Seven := a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7;
end;

procedure Register4(a, b, c, d: Integer; const pn: array of AnsiString);
var i: Integer;
begin
  for i := 0 to d - 1 do Out[i] := pn[i];
end;

var names: array[0..3] of AnsiString;
begin
  writeln('six=', Six(1, 2, 3, 4, 5, 6));
  writeln('seven=', Seven(1, 2, 3, 4, 5, 6, 7));
  names[0] := 'alpha';
  names[1] := 'beta';
  names[2] := 'gamma';
  Register4(9, 9, 9, 3, names);
  writeln('oa=', Out[0], ',', Out[1], ',', Out[2]);
end.
