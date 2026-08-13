program test_fpc_float_errors;
{ --fpc-float-errors (feature-float-exception-mask-control, slice 2): the
  opt-in that makes pxx report float faults the way FPC does.

  pxx's default is quiet IEEE and stays it — this same program compiled WITHOUT
  the flag prints an Inf and exits 0, which is half of what the Makefile checks.
  With the flag, the entry unmasks exactly what FPC unmasks (invalid /
  zero-divide / overflow — measured with FPC's own GetExceptionMask, not
  assumed) and a SIGFPE hook decodes si_code into the matching runtime error:

      1.0/0.0    -> Runtime error 208, exit 208
      1e308*10   -> Runtime error 205, exit 205
      0.0/0.0    -> Runtime error 207, exit 207

  Those three numbers are FPC's, measured by running the same three lines under
  FPC 3.x on this box. The `none` case exists to prove the flag does not fire
  spuriously: an unmasked program that never triggers an exception must run to
  completion normally. }

var
  a, b, r: Double;
  which: AnsiString;

begin
  which := '';
  if ParamCount >= 1 then which := ParamStr(1);
  a := 1.0; b := 0.0; r := 0.0;
  if which = 'div' then
    r := a / b
  else if which = 'ovf' then
  begin
    a := 1e308; b := 10.0;
    r := a * b;
  end
  else if which = 'inv' then
  begin
    a := 0.0; b := 0.0;
    r := a / b;
  end
  else
    r := a + b;
  WriteLn('no trap, r=', r);
end.
