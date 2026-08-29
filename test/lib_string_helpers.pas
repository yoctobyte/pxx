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

  `Length` WORKS now and is still not gated here, which needs explaining.

  It is a PROPERTY in FPC over a PRIVATE `GetLength`, and pxx dispatched only
  METHODS through a type helper — so the surface's most-used member was the one
  that did not work while every sibling did. Widening the helper guard in
  `pasparser_lval.inc` fixed it, with no change to the library declaration,
  which had been written the FPC way and left platonic for exactly that moment.

  But THIS file is built by `$(PXX_STABLE)`, the pinned binary, and the pin
  predates that fix — so a `Length` row here reds `lib-test` on a compiler that
  is correct. Track B's gate can only ever assert what the PIN can do, which
  means a library feature riding an unpinned compiler fix is ungatable here
  until the pin moves. The mechanism is gated meanwhile by
  `test/test_type_helper_property.pas` in `test-core`, which builds with the
  freshly-built compiler.

  AT THE NEXT PIN: add `writeln('Length=', s.Length);` as the first row and
  regenerate `.expected` with the command in the Makefile rule. Nothing else
  changes. Verified against the post-fix compiler: 35 rows, byte-identical.
  It was NOT left out because `s.GetLength` could substitute — that would gate
  a member FPC does not expose, since the accessor is private there. }
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
