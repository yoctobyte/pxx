program test_setsignalhandler_call;
{ A HAND-WRITTEN SetSignalHandler, which is the one shape the PXX_HAS_SIGNALS
  predicate does NOT cover: the Pascal parser accepts this call on every target
  and leaves the refusal to the backend, so a target with no signal runtime has
  to say so from ir_codegen_<target>.inc or not at all.

  On wasm32 it said nothing until 2026-09-04. The program compiled rc=0, the
  module VALIDATED, and it trapped with `wasm trap: unreachable` on this line --
  the failure mode wasm32's coverage report exists to prevent, arriving through
  the one path that report cannot see, because a refused body IS the report.

  This file is BUILT AND EXPECTED TO FAIL on wasm32 (the Makefile checks the
  rc and the wording). It compiles and runs normally on the five hosted
  targets, so it is not a *_fail.pas: what it asserts is per target. }
procedure H(n: Integer);
begin
  WriteLn('handler ', n);
end;
begin
  SetSignalHandler(2, @H);
  WriteLn('installed');
end.
