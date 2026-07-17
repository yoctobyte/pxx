program test_parallel_for_capture_string;
{ `parallel for` ansistring capture (unblocked by the p^[k] string-index fix):
  read Length, char-index, and compare a captured string across workers.
  --threadsafe, x86-64. }
uses palparallel;
const N = 1000;
var lens: array[0..N-1] of Integer;
    codes: array[0..N-1] of Integer;
procedure Run;
var s: AnsiString; i, lenErr, codeErr: Integer;
begin
  s := 'ABCDE';
  parallel for i := 0 to N-1 do
  begin
    lens[i]  := Length(s);                 { captured-string Length }
    codes[i] := Ord(s[(i mod 5) + 1]);     { captured-string char index }
  end;
  lenErr := 0; codeErr := 0;
  for i := 0 to N-1 do
  begin
    if lens[i] <> 5 then Inc(lenErr);
    if codes[i] <> 65 + (i mod 5) then Inc(codeErr);
  end;
  writeln('lenErr=', lenErr);
  writeln('codeErr=', codeErr);
  if (lenErr = 0) and (codeErr = 0) then writeln('PARFORSTR OK') else writeln('PARFORSTR FAIL');
end;
begin Run; end.
