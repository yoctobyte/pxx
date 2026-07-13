{ A value cast to an ordinal type NAMED BY AN IDENTIFIER: `WideChar(x)`, `QWord(x)`,
  `NativeInt(x)`.

  The builtin casts key on the type KEYWORD token (tkInteger_T, tkChar_T, ...), so a type
  whose name merely lexes as an identifier had NO cast at all and came out as "undefined
  variable". Byte(x) and Word(x) worked; WideChar(x) did not, purely because of how it
  lexes.

  These are real width-truncating casts (AN_PTR_CAST), not the Integer/LongWord value-pun,
  so the narrowing below must actually narrow. A variable, routine or user type alias of the
  same name still wins. }
program test_ident_ordinal_cast_b286;

var
  i: Integer;
  n: Int64;
begin
  i := 300;
  writeln('Byte(300)     = ', Byte(i),      ' (44)');
  writeln('Word(300)     = ', Word(i),      ' (300)');
  writeln('WideChar(65)  = ', Ord(WideChar(65)), ' (65)');
  writeln('WideChar(300) = ', Ord(WideChar(i)),  ' (300)');

  n := $1FFFFFFFF;
  writeln('Cardinal(...) = ', Cardinal(n),  ' (4294967295)');
  writeln('QWord(-1)     = ', QWord(Int64(-1)));
  writeln('NativeInt(5)  = ', NativeInt(5), ' (5)');
end.
