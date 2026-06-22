program test_keyword_array_case;

{ Keywords are case-insensitive in user code (only the compiler's own source is
  {$CASESENSITIVE ON}). The lexer keyword table matched `array` by lowercase
  literal chars only, so capitalised `Array` / `ARRAY` fell through to an
  identifier — a real Synapse blocker: synacode.pas:344 has a SECOND open-array
  parameter (`... ; var ArLong: Array of Integer`), which made the parser report
  "Expected ), but got of". Exercise mixed-case `array` across the spots that
  matter: two open-array parameters (one `array`, one `ARRAY`) and capitalised
  `Array` variable declarations. Output: 36 / 5. }

function Sum2(a: array of Integer; b: ARRAY of Integer): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(a) do Result := Result + a[i];
  for i := 0 to High(b) do Result := Result + b[i];
end;

var
  p: Array of Integer;
  q: Array of Integer;
  i: Integer;
begin
  SetLength(p, 3);
  SetLength(q, 2);
  for i := 0 to 2 do p[i] := i + 1;   { 1 2 3 }
  q[0] := 10; q[1] := 20;
  WriteLn(Sum2(p, q));                 { 6 + 30 = 36 }
  WriteLn(Length(p) + Length(q));      { 5 }
end.
