program p;
uses c_import_bitfields;
var f: flags_t; s: sym_t; w: PLongWord;
begin
  w := PLongWord(@f);
  FillChar(f, SizeOf(f), 0); f.b := 1;   writeln('b=1      word=', w^, '  want 2');
  FillChar(f, SizeOf(f), 0); f.c := 5;   writeln('c=5      word=', w^, '  want 20');
  FillChar(f, SizeOf(f), 0); f.d := 700; writeln('d=700    word=', w^, '  want 44800');
  FillChar(f, SizeOf(f), 0); f.b := 1; f.c := 5; f.d := 700; writeln('b,c,d    word=', w^, '  want 44822 (C says ', c_flags_word, ')');
  w^ := 44822; writeln('read back b=', f.b, ' c=', f.c, ' d=', f.d, '  want 1 5 700');
  FillChar(s, SizeOf(s), 0); s.d0 := 3; s.l0 := 1; s.d1 := 10;
  writeln('sym word=', s.val, '  want ', 3 or (1 shl 15) or (10 shl 16));
end.
