{ SPDX-License-Identifier: MPL-2.0 }
{ SHARED COMPILER UTILITIES — belonging to no frontend and no backend.

  Small helpers the whole compiler uses. The bar for landing here is that a
  build with ANY single frontend or backend omitted still needs it
  (feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets);
  anything one language or one target owns belongs in that language's or that
  target's file instead.

  Included immediately after lexer.inc — not earlier, which is where it wants
  to go. AppendChar, an equally general string helper, is itself defined in
  lexer.inc, so a utility file placed before it cannot use it. That is the same
  finding one level down and is left alone deliberately: moving AppendChar
  touches the two FPC-vs-self-host variants at lexer.inc:331/352 and is not
  part of a mechanical move. }

{ The compiler's own IntToStr. The `A` is for AnsiString, not for Ada — its
  body lived in aparser.inc (the ~460-line Ada skeleton) until 2026-08-19,
  which meant the Pascal parser, the NilPy parser, the C parser and the C
  preprocessor all depended on the Ada frontend being compiled in. Omitting Ada
  was the only reason anybody noticed: `-dPXX_NO_ADA` left one unsolved forward
  and nothing else. A shared utility marooned in a skeleton frontend is
  invisible while every frontend is always built, which is exactly why the
  omission defines keep finding things reading the code does not.

  KNOWN DEFECT, moved verbatim rather than fixed here so that this move stays
  provably mechanical: `while n > 0` means a NEGATIVE n yields the empty string
  ('' , not '-5'). Filed as bug-a-aintostr-returns-empty-for-negative-numbers. }
function AIntToStr(n: Integer): AnsiString;
var rev, res: AnsiString; i: Integer;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do
    begin
      AppendChar(rev, Chr(Ord('0') + (n mod 10)));
      n := n div 10;
    end;
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;
