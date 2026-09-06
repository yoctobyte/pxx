program test_a_parameterless_generic_routine_is_called_without_parentheses;
{ A generic routine taking no VALUE parameters is called `specialize F<T>` with
  no `()` -- Pascal's one spelling for a parameterless call. The call-site
  predicate required a trailing `(`, which is the right guard for the BARE
  Delphi surface (`F<A>` is ambiguous with `a < b > (c)`) and the wrong one for
  the KEYWORD surface, where `specialize` already settles that it is not a
  comparison. Declining left the run in the stream and the reader was told
  `undefined variable (specialize)`.
  Rows 1-2 are the shape that was refused; 3-6 are the spellings that already
  worked and must keep working; 7-8 are the comparison chains the `(` guard
  exists to protect, which must still be read as comparisons.
  tgenfunc19.pp is the corpus row. }
{$mode objfpc}
type
  TT = class
    class function Test: LongInt; static;
  end;
  TU = class(TT)
    class function Test: LongInt; static;
  end;

class function TT.Test: LongInt; begin Result := 1; end;
class function TU.Test: LongInt; begin Result := 2; end;

generic function DoTest<T: TT>: LongInt;
begin Result := T.Test; end;

generic function Twice<T>(a: T): T;
begin Result := a + a; end;

var a, b, c: LongInt;
begin
  WriteLn('1 ', specialize DoTest<TT>);
  WriteLn('2 ', specialize DoTest<TU>);
  if specialize DoTest<TU> <> 2 then WriteLn('3 BAD') else WriteLn('3 ok');
  WriteLn('4 ', specialize DoTest<TT>());
  WriteLn('5 ', specialize Twice<LongInt>(21));
  WriteLn('6 ', specialize Twice<AnsiString>('ab'));
  a := 1; b := 2; c := 3;
  WriteLn('7 ', a < b, ' ', b > c);
  WriteLn('8 ', (a < b) and (c > b));
end.
