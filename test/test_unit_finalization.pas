{$mode objfpc}
program test_unit_finalization;

{ A unit's `finalization` section must run after the main body, in REVERSE
  init (dependency) order — and on Halt too, like FPC
  (bug-unit-finalization-not-executed). The Halt leg lives in
  test_unit_finalization_halt.pas (separate binary: Halt ends the process). }

uses ufin2, ufin;

begin
  Touch2;
  writeln('main done');
end.
