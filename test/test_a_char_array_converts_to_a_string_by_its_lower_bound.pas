program test_a_char_array_converts_to_a_string_by_its_lower_bound;
{ FPC 3.2.2's rule, measured: a ZERO-BASED char array in a string context
  reads as a PChar and stops at the first #0. Any other lower bound converts
  ALL its characters, NULs included, for Write, assignment and concatenation
  alike. pxx stopped at #0 for every array. Each byte of the output matches fpc
  (the brackets show the NULs).
  bug-a-a-char-array-in-a-string-context-stops-at-the-first-nul-and-fpc-does-not }
type TRec = record z: array[0..3] of Char; o: array[1..4] of Char; end;
     TArr = array[1..4] of Char; PArr = ^TArr;
var z: array[0..3] of Char = 'pq'; o: array[1..4] of Char = 'pq'; t: array[2..5] of Char = 'pq';
    r: TRec; p: PArr; s: AnsiString; buf: array[0..7] of Char;
begin
  Write('['); Write(z); Write('|'); Write(o); Write('|'); Write(t); WriteLn(']');
  s := z; Write(Length(s)); s := o; Write(' ', Length(s)); s := t; WriteLn(' ', Length(s));
  s := 'a' + o; Write(Length(s)); s := 'a' + z; WriteLn(' ', Length(s));
  r.z := 'ab'; r.o := 'ab';
  s := r.z; Write(Length(s)); s := r.o; WriteLn(' ', Length(s));
  New(p); p^ := 'xy'; s := p^; WriteLn(Length(s)); Dispose(p);
  buf := 'ABC'; buf[4] := 'E'; s := buf; WriteLn(s, ' ', Length(s));
end.
