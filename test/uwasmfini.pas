{ Unit for test_a_unit_finalization_runs_on_wasm32. }
unit uwasmfini;

interface

var
  Tag: AnsiString;

implementation

initialization
  Tag := 'set by init';
finalization
  WriteLn('fini uwasmfini (', Tag, ')');
end.
