program test_hex_char_code;
{ #NN char-code literals across all radices, in statement and const context.
  Regression for bug-hex-char-code-literal (#$/#%/#& were decimal-only). }
type TSpecials = set of char;
const
  CFF: char = #$FF;                                   { hex const }
  URLSpecialChar: TSpecials = [#$00..#$20, #$2F, #$7F..#$FF];  { subrange set const (synacode.pas:94) }
var
  c: char;
begin
  c := #$41;       writeln(Ord(c));    { 65 }
  c := #%01000001; writeln(Ord(c));    { 65 }
  c := #&101;      writeln(Ord(c));    { 65 }
  c := #65;        writeln(Ord(c));    { 65 }
  writeln(Ord(CFF));                   { 255 }
  if #$10 in URLSpecialChar then writeln('lo');   { lo }
  if #$80 in URLSpecialChar then writeln('hi');   { hi }
  if not (#$41 in URLSpecialChar) then writeln('ex'); { ex }
end.
