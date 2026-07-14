program test_cross_str_length_index;

{ Cross-target managed-AnsiString Length + char-indexing oracle (compile with
  -dPXX_MANAGED_STRING). Reading Length(s) and s[i], and writing s[i], require
  IR_LEA of a scalar managed string to auto-load the heap handle in read mode
  (not the slot address). Output is identical on every target as on x86-64. }

var
  s, t: AnsiString;
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

  { b355: a write whose INDEX EXPRESSION reads the string being written.
    Every backend but x86-64 left InLValueWrite set while emitting the index,
    so Length(t) inside the index read t's SLOT ADDRESS as a handle — garbage
    length, wild store: silently lost on small strings, SIGSEGV on big ones
    (bug-arm32-chacha20poly1305-segfault's tamper-flip line). }
  s := 'hello world';
  t := s;                                          { shared -> COW on write }
  t[Length(t)] := Chr(Ord(t[Length(t)]) xor 1);
  writeln(s);                    { hello world }
  writeln(t);                    { hello worle }
end.
