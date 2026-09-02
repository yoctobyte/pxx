{ SPDX-License-Identifier: MPL-2.0 }
unit realunit;
{ The OTHER direction. prog.pas names this one itself, so it MUST bind from
  this directory: a guard that skipped SourceFileDir for every unit rather than
  for injected ones would break here, and pass everything else in this test. }
interface
function Answer: Integer;
implementation
function Answer: Integer;
begin
  Answer := 42;
end;
end.
