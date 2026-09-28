{ Unit for test_a_unit_initialization_runs_on_wasm32: the `begin` form of a
  unit's initialization, which must run AFTER uwasminita's (it uses it). }
unit uwasminitb;

interface

uses uwasminita;

var
  B: AnsiString;
  N: Integer;

implementation

begin
  B := A + 'b';
  N := 42;
end.
