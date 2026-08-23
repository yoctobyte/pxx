{ A POINTER TO PChar — `^PChar` and its FPC spelling PPChar — in every context
  that has to recognise a C string, plus Length over a plain PChar.

  Half of these looked correct before: `AnsiString(<any pointer>)` converts its
  operand as a PChar unconditionally, so the cast and assignment spellings were
  right by a blanket rule that never inspected the type. WriteLn, concat, Length
  and comparison are the contexts that refuse to guess, and every one of them
  answered with the POINTER.

  Every row measured against fpc 3.2.2 on this same source.
  refactor-centralize-managed-string-pchar-conversion }
program test_pchar_pointer_to_pchar;
var
  sa: AnsiString;
  a: PChar;
  q: ^PChar;
  pp: PPChar;
  s: AnsiString;
begin
  sa := 'abcde';
  a := PChar(sa);
  q := @a;
  pp := @a;

  { the deref: the shape the fix is about }
  writeln(q^);
  writeln('x' + q^);
  writeln(q^ + 'y');
  s := q^; writeln(s);
  writeln(AnsiString(q^));
  writeln(Length(q^));
  writeln(q^ = 'abcde');
  writeln(q^ <> 'abcde');

  { PPChar is the same type under FPC's own name — `char**`, i.e. argv }
  writeln(pp^);
  writeln('y' + pp^);
  writeln(pp[0]);
  writeln('z' + pp[0]);
  writeln(pp^ = 'abcde');
  writeln(Length(pp^));

  { and a plain PChar's Length, which answered with the address while
    Length(arrayOfPChar[0]) beside it answered 5 }
  writeln(Length(a));
  writeln(Length(a + 1));
end.
