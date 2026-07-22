{$mode objfpc}
program test_unit_finalization_halt;

{ Halt must run unit finalization sections before exiting (FPC parity), and
  keep the exit code (bug-unit-finalization-not-executed). }

uses ufin2;

begin
  writeln('before halt');
  Halt(3);
  writeln('never');
end.
