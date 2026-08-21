program test_widechar_no_cast_in_program;
{ A WideChar reaching a string context in a program that contains NO
  `WideChar(` cast anywhere.

  That combination used to be a hard COMPILE ERROR — "WideChar->string
  conversion: __pxxWideCharToUTF8 helper not loaded" — because the token
  pre-scan pulled the builtin unit only for a `widechar(` CAST, on the stated
  reasoning that WideChar, unlike UCS4Char, is not a declarable type. It is one.
  Every existing test that exercised the conversion happened to write the cast,
  so the gap survived: the failure needs the ABSENCE of a construct, which no
  test asserts by accident.

  Deliberately spells no cast, and pins the ASCII case where pxx's UTF-8
  encoding and FPC's codepage answer agree byte for byte — a non-ASCII code
  unit differs by design (pxx encodes UTF-8, FPC uses the system codepage) and
  would make this a test of the encoding policy rather than of the pull.
  refactor-centralize-managed-string-pchar-conversion }

type
  TRec = record w: WideChar; end;

var
  w: WideChar;
  r: TRec;
  arr: array[0..1] of WideChar;
  s: AnsiString;

procedure Show(const t: AnsiString);
begin
  WriteLn(Length(t), ' ', t);
end;

begin
  w := 'A';
  r.w := 'B';
  arr[0] := 'C';

  s := w;              WriteLn(Length(s), ' ', s);     { 1 A }
  s := 'x' + w;        WriteLn(Length(s), ' ', s);     { 2 xA }
  s := w + 'x';        WriteLn(Length(s), ' ', s);     { 2 Ax }
  s := r.w;            WriteLn(Length(s), ' ', s);     { 1 B }
  s := 'y' + arr[0];   WriteLn(Length(s), ' ', s);     { 2 yC }
  Show(w);                                             { 1 A }
end.
