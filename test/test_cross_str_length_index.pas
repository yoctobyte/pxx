program test_cross_str_length_index;

{ Cross-target managed-AnsiString Length + char-indexing oracle (compile with
  -dPXX_MANAGED_STRING). Reading Length(s) and s[i], and writing s[i], require
  IR_LEA of a scalar managed string to auto-load the heap handle in read mode
  (not the slot address). Output is identical on every target as on x86-64. }

var
  s: AnsiString;
  i: Integer;
  ch: Char;
begin
  s := 'hello';
  writeln(Length(s));            { 5 }
  writeln(s[1]);                 { h }
  writeln(s[5]);                 { o }

  ch := s[3];
  writeln(ch);                   { l }

  { build a string by index after SetLength }
  SetLength(s, 4);
  for i := 1 to 4 do
    s[i] := Chr(96 + i);         { abcd }
  writeln(s);
  writeln(Length(s));            { 4 }

  { shrink then read back }
  SetLength(s, 2);
  writeln(s);                    { ab }
  writeln(s[2]);                 { b }
  writeln(Length(s));            { 2 }
end.
