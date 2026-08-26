{ The poisoned unit for test_unit_stray_token_refused: `cosnt` is a typo for
  `const`, and everything after it used to be discarded without a word. }
unit ustray;
interface
cosnt K = 5;
function F: Integer;
implementation
function F: Integer; begin F := K; end;
end.
