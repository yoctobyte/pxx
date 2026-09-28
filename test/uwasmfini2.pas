{ Unit for test_a_unit_finalization_runs_on_wasm32: uses uwasmfini, so it is
  initialised after it and must be FINALISED before it. }
unit uwasmfini2;

interface

uses uwasmfini;

implementation

finalization
  WriteLn('fini uwasmfini2, before uwasmfini');
end.
