program esp_a_string_grows_past_its_doubled_size;
{ Grow one string to 112 KB in 1 KB appends. Growth used to request double
  the needed size, so at ~90 KB an S3 asked for ~180 KB and ran out of heap.
  On ESP the slack is now capped at 16 KB. }
var s, chunk: AnsiString; i, sum: Integer;
begin
  SetLength(chunk, 1024);
  for i := 1 to 1024 do chunk[i] := Chr(65 + i mod 26);
  s := '';
  for i := 1 to 112 do s := s + chunk;
  sum := 0;
  for i := 1 to Length(s) do sum := (sum + Ord(s[i])) and $FFFFFF;
  WriteLn('PXX-strgrow len=', Length(s), ' sum=', sum);
end.
