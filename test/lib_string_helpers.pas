{ Delphi's TStringHelper surface on AnsiString (feature-p-delphi-string-helpers).

  THE ORACLE IS THE POINT. `lib_string_helpers.expected` is fpc 3.2.2's own
  stdout for THIS FILE, compiled under {$modeswitch typehelpers} — not a
  hand-written table. Both compilers build this source unmodified, so the
  expectation is regenerable in one command (it is in the Makefile rule) rather
  than being our own behaviour written down.

  Indexing is 0-BASED, which is Delphi's convention and not Pascal's, and that
  is the whole reason this file exists: `s.Substring(2)` drops two characters
  where `Copy(s, 2, n)` keeps from the second, and `s.IndexOf` answers one less
  than `Pos`. A wrong conversion here is a silent wrong answer, never a crash,
  so the rows below deliberately include the boundaries where the two
  conventions disagree most: absent needles (-1, not 0), out-of-range and
  negative Substring starts, a pad narrower than the string, and Split on ''
  (which is ONE empty element, not none).

  NOT COVERED, and there is no way to cover it today: `s.Length`. FPC declares
  Length as a PROPERTY and pxx does not dispatch a property through a type
  helper — bug-p-a-type-helper-cannot-declare-a-property. The obvious
  substitute does not exist either: FPC declares the `GetLength` accessor
  PRIVATE, so `s.GetLength` is an `Illegal qualifier` there and cannot appear
  in a file both compilers build. The declaration in sysutils stays platonic
  rather than being respelled as a method; when that bug is fixed, add
  `writeln('Length=', s.Length);` here and the oracle covers it with no other
  change. Until then this surface's most-used member is genuinely ungated, and
  saying so is better than a row that gates something else. }
program lib_string_helpers;
{$mode objfpc}{$H+}{$modeswitch typehelpers}
uses sysutils;
var
  s: AnsiString;
  a: TStringArray;
  i: Integer;
begin
  s := '  Hello World  ';
  writeln('IsEmpty=', s.IsEmpty);
  writeln('Trim=[', s.Trim, ']');
  writeln('TrimLeft=[', s.TrimLeft, ']');
  writeln('TrimRight=[', s.TrimRight, ']');
  writeln('ToUpper=[', s.ToUpper, ']');
  writeln('ToLower=[', s.ToLower, ']');

  s := 'Hello World';
  writeln('Substring2=[', s.Substring(2), ']');
  writeln('Substring2_3=[', s.Substring(2, 3), ']');
  writeln('IndexOf_o=', s.IndexOf('o'));
  writeln('LastIndexOf_o=', s.LastIndexOf('o'));
  writeln('StartsWith=', s.StartsWith('Hell'));
  writeln('EndsWith=', s.EndsWith('rld'));
  writeln('Contains=', s.Contains('lo W'));
  writeln('PadLeft14=[', s.PadLeft(14), ']');
  writeln('PadRight14=[', s.PadRight(14), ']');

  { the boundaries where 0-based and 1-based disagree }
  s := 'a-b-a';
  writeln('Replace=[', s.Replace('a', 'X'), ']');
  writeln('ReplaceFirst=[', s.Replace('a', 'X', []), ']');
  writeln('IndexOf_missing=', s.IndexOf('zz'));
  writeln('LastIndexOf_missing=', s.LastIndexOf('zz'));
  writeln('IndexOf_from1=', s.IndexOf('a', 1));

  s := 'abc';
  writeln('Substring1=[', s.Substring(1), ']');
  writeln('Substring9=[', s.Substring(9), ']');
  writeln('Substring1_99=[', s.Substring(1, 99), ']');
  writeln('SubstringNeg=[', s.Substring(-1), ']');
  writeln('PadLeft2=[', s.PadLeft(2), ']');
  writeln('PadLeft5dot=[', s.PadLeft(5, '.'), ']');
  writeln('PadRight5dot=[', s.PadRight(5, '.'), ']');

  s := 'a,,b';
  a := s.Split([',']);
  writeln('SplitCount=', Length(a));
  for i := 0 to High(a) do writeln('  Split', i, '=[', a[i], ']');

  s := '';
  writeln('emptyIsEmpty=', s.IsEmpty);
  a := s.Split([',']);
  writeln('emptySplitCount=', Length(a));
  writeln('STRHELP OK');
end.
