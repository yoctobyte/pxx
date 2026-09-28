{ Every unit's initialization section runs, in dependency order, before the
  program body -- on wasm32 too.

  A wasm32 `main` is synthesised from the program body's chunks, and the
  driver's calls to the unit initialisers were emitted as machine code that
  build never reached, so on wasm32 NO unit's initialization ran: a unit
  variable set there read 0; SysUtils' month names were empty and its
  separators NUL (`%n` printed `1 234 .50`); and textfile's Output/StdErr
  handles stayed 0, so every Text write went to fd 0 and died with Runtime
  error 9. Expected output is FPC 3.2.2's, on both streams. }
program test_a_unit_initialization_runs_on_wasm32;
{$mode objfpc}
uses SysUtils, uwasminitb;

var
  f: Text;   { the Text RTL, so StdErr below is its Text variable }
  G: Integer = 5;

begin
  WriteLn(B, ' ', N, ' ', G);
  WriteLn(Format('%s|%n', [ShortMonthNames[3], 1234.5]));
  WriteLn('[', DecimalSeparator, ThousandSeparator, ']');
  WriteLn(Output, 'to output');
  WriteLn(StdErr, 'to stderr');
end.
