program test_cdecl_warning_only_where_ignored;

{ `--warn-ignored-directives` must stay SILENT about `cdecl` where the
  directive selects a convention, and speak only where it is really ignored.

  It asked "is this x86-64" and so said "documentation only" on i386, aarch64
  and arm32 as well. There `cdecl` is load-bearing: removing it from Twice
  makes the compiler refuse `f := @Twice` (a Pascal routine into a cdecl
  type), and v448, before that refusal existed, printed 0.0 instead of 42.0.
  The warning now asks TargetSelectsCdecl, the same list the refusal asks.
  Found by frankd-90. }

type
  TF = function(x: Double): Double; cdecl;

function Twice(x: Double): Double; cdecl;
begin
  Twice := 2 * x;
end;

var
  f: TF;
begin
  f := @Twice;
  WriteLn(f(21.0):0:1);
end.
