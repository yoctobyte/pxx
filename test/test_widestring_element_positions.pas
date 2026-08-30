program test_widestring_element_positions;
{ `w[i]` on a UTF-16 string is a WIDECHAR VALUE, in every position it can
  appear in -- not only where somebody remembered to add an arm.

  ENUMERATED BY POSITION, NOT BY ENTITY, and that is the point of the file.
  test_widestring_lowering enumerates the six ENTITIES that carry a string's
  element width (variable, alias, field, UnicodeString, array element, function
  result) and was blind to arguments, because an argument is not an entity --
  it is a POSITION. A matrix inherits the shape of the list it was derived
  from. So this one is derived from the positions an element value can occupy:
  Ord, Write, concat, a string argument, a string assignment, a WideChar
  destination, a comparison operand, an element store, and a loop.

  Before the fix only the FIRST of those was right. ir.inc took the width off
  the ADDRESS node, which fixed the READ; every other position saw a node the
  parser had typed tyChar and got the code unit's low byte -- correct on all of
  ASCII, wrong on everything else, silently. The fix is one line at the one
  site that decides a string index's element kind, after which the existing
  WrapWideCharToUTF8 path serves every position at once.

  NOT AN FPC ORACLE, and the same divergence as test_widestring_surrogate_pair:
  FPC agrees on `units=2`, on `Ord` (233), and on the comparison, and answers
  ONE byte wherever a wide element reaches a byte string, because its
  WideChar-to-AnsiString conversion goes through DefaultSystemCodePage and
  yields Latin-1. pxx's AnsiString is UTF-8 by construction, so it answers the
  two bytes of U+00E9. Measured, not assumed.

  The string is built with explicit WideChar($63)/WideChar($E9) rather than a
  source literal so that both compilers hold the same two code units and the
  comparison is about the ELEMENT, not about either one's source codepage. }
{$define PXX_WIDE_PAYLOAD}
var
  w, w2: WideString;
  s: AnsiString;
  c: WideChar;
  i: Integer;

procedure TakesStr(a: AnsiString);
begin
  writeln('4 argument =', a, ' bytes=', Length(a));
end;

begin
  w := WideChar($63) + WideChar($E9);        { 'c' + U+00E9 }
  writeln('units=', Length(w));
  writeln('1 Ord      =', Ord(w[2]));
  writeln('2 Write    =', w[2]);
  s := 'x' + w[2];
  writeln('3 concat   =', s, ' bytes=', Length(s));
  TakesStr(w[2]);
  s := w[2];
  writeln('5 assign   =', s, ' bytes=', Length(s));
  c := w[2];
  writeln('6 towchar  =', c, ' ord=', Ord(c));
  writeln('7 compare  =', w[1] = 'c');
  w2 := 'ab';
  w2[1] := w[2];
  writeln('8 elemstore=', w2, ' units=', Length(w2));
  write('9 loop     =');
  for i := 1 to Length(w) do write(w[i]);
  writeln;
end.
