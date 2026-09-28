{ Unit for test_a_unit_initialization_runs_on_wasm32: the `initialization`
  form, reading a typed constant (global initialisers must already be in place
  when a unit's initialization runs). Finalization is
  test_a_unit_finalization_runs_on_wasm32's. }
unit uwasminita;

interface

const
  Seps: array[0..1] of Char = (',', ':');

var
  A: AnsiString;

implementation

initialization
  A := 'a' + Seps[1];
end.
