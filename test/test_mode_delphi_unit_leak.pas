{$mode delphi}
program test_mode_delphi_unit_leak;
{ A {$mode delphi} PROGRAM that `uses` a {$MODE PXX} unit must still be in
  delphi mode afterwards.

  It was not. ParseUsesUnitBody saved and restored NestedComments across a unit
  load but not DelphiMode — and ONE line in lexer.inc's {$mode} handler sets
  both, so half the directive leaked. Invisible for months because every mode a
  unit actually declared set DelphiMode to its default value anyway; then 136
  lib/rtl units gained {$MODE PXX}, and any `uses` of the RTL turned
  {$mode delphi} off for the rest of the program. Five test-core tests went red
  at once.

  The assertion is the at-optional procedural value — `p := Fn` with no `@`,
  which is delphi-only — written AFTER the uses clause, so it can only compile
  if the mode survived the unit load.
  bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program }
{ ORDER MATTERS, and it is the negative control: the {$MODE PXX} unit is named
  LAST, so on a leaking compiler DelphiMode ends up OFF here. Written the other
  way round this program compiles even when broken, because delphidial's own
  {$mode delphi} leaks ON and hides the bug — measured on `pinned`, which
  accepts it. }
uses delphidial, pxxdial;

type TFn = function(x: Integer): Integer;

var p: TFn;

function Dbl(x: Integer): Integer;
begin
  Dbl := x * 2;
end;

begin
  p := Dbl;                     { delphi: no @ needed. Rejected in the default mode. }
  writeln('p7=', p(7));
  writeln('pxx=', PxxDialAnswer, ' delphi=', DelphiDialAnswer);
end.
