program test_mode_delphi_unit_leak_off_fail;
{ The other arm, and the reason this is two tests: a program in the DEFAULT
  mode that `uses` a {$mode delphi} unit must NOT inherit delphi mode. Same
  save/restore, opposite direction — and a fix that only stopped the OFF leak
  would pass the sibling test and still be half a fix.

  `p := Dbl` with no `@` is delphi-only, so this program must be REFUSED. The
  unit it uses compiles fine in its own mode, which is the point: the mode is
  the unit's business and stops at its boundary.
  bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program }
uses delphidial;

type TFn = function(x: Integer): Integer;

var p: TFn;

function Dbl(x: Integer): Integer;
begin
  Dbl := x * 2;
end;

begin
  p := Dbl;                     { must not compile: this program is not delphi }
  writeln('p7=', p(7), ' ', DelphiDialAnswer);
end.
