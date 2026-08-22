program test_widechar_writeln_prints_the_character;
{ WriteLn(w) where w: WideChar must print the CHARACTER, not its 16-bit ordinal.
  Before tyWideChar existed, WideChar collapsed to tyUInt16 and every OTHER
  string context recognised it by "a Word here can only mean a widechar" —
  a fallback writeln cannot use, because WriteLn(someWord) must print the
  number. So writeln alone printed 65 for 'A'. bug-a-writeln-of-a-widechar-
  prints-its-ordinal.

  ASCII only, deliberately: pxx converts a WideChar to its UTF-8 encoding while
  FPC converts through the system codepage, so a non-ASCII code unit is a KNOWN
  and intended divergence and would make this test unable to compare against the
  oracle. See devdocs/dev/pascal-dialect-divergences.md. }
{$mode objfpc}{$H+}
type
  TRec = record w: WideChar; end;
var
  w, w2: WideChar;
  pw: PWideChar;
  buf: array[0..3] of WideChar;
  r: TRec;
  arr: array[1..3] of WideChar;
  i: Integer;
  s: AnsiString;

function MkW(x: WideChar): WideChar; begin Result := x; end;
procedure Bump(var x: WideChar); begin Inc(x); end;

begin
  { the shapes that were all printing ordinals }
  w := 'A';                 WriteLn(w);
  WriteLn(WideChar(66));
  r.w := 'C';               WriteLn(r.w);
  arr[1] := 'D';            WriteLn(arr[1]);
  WriteLn(MkW('E'));
  w := 'F';                 WriteLn(w, w);
  w := 'G';                 WriteLn('[', w, ']');
  w := 'H';                 Write(w); WriteLn;

  { ...while the ORDINAL readings, which the new type kind could have broken,
    all still hold. A WideChar is as much an ordinal as a Word is; only its
    CONVERSION to a string differs. }
  w := 'A';                 WriteLn(Ord(w));
  WriteLn(w < 'B', ' ', w = 'A');
  w2 := 'B';                WriteLn(w < w2);
  Inc(w);                   WriteLn(Ord(w));
  Dec(w, 2);                WriteLn(Ord(w));
  WriteLn(Ord(Succ(w)), ' ', Ord(Pred(w)));
  w := 'B';
  case w of
    'A': WriteLn('is-a');
    'B': WriteLn('is-b');
  else   WriteLn('other');
  end;
  w := 'A';  Bump(w);       WriteLn(Ord(w));
  WriteLn(SizeOf(w), ' ', SizeOf(WideChar));
  i := 0;
  for i := 65 to 67 do begin w := WideChar(i); Write(Ord(w), ' '); end;
  WriteLn;

  { ...and so do the string contexts that always worked }
  w := 'A';  s := w;        WriteLn(Length(s), ' ', s);
  s := 'x' + w;             WriteLn(s);
  s := w + 'x';             WriteLn(s);

  { the sibling arm: the ELEMENT of a PWideChar is a WideChar, so p^ prints the
    character too. This said tyUInt16 until the same grep that closed the bug
    above found it (normalise-dont-special-case: fix one arm, check the other). }
  buf[0] := 'P'; buf[1] := 'Q'; buf[2] := WideChar(0);
  pw := @buf[0];
  WriteLn(pw^);
  WriteLn(Ord(pw^));
  Inc(pw);
  WriteLn(pw^);
end.
