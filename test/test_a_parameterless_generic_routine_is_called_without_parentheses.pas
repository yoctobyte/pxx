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
  tgenfunc19.pp is the corpus row.

  THE SIBLING SPELLING IS NOT IN THIS FILE AND CANNOT BE, which is why it is
  named here instead. `specialize Max<Integer> as MaxIntF;` is the
  specialization-ALIAS DECLARATION, and it differs from the parameterless CALL
  in rows 1-2 by exactly one token: `as` where a call has `(`. So the `(` this
  fix removed had a SECOND, UNDOCUMENTED job -- keeping the call-site sweep off
  that declaration -- and removing it for a good reason took that job too: the
  sweep rewrote the run to `Max_Integer`, ate the keyword, and the reader
  reported `expected 'begin' before 'Max_Integer'`, a complaint about the
  declaration section ending, three phases after the rewrite that caused it.
  Two prio-70 rows went red (test_generic_func,
  test_inline_generic_specialization) and neither is reachable from here.

  It cannot live in this file because THIS file is an fpc differential and the
  alias form is a pxx EXTENSION -- fpc 3.2.2 answers `Syntax error, "BEGIN"
  expected but "identifier SPECIALIZE" found`. Putting it here would cost the
  oracle to gain a row that already exists elsewhere. So: the two spellings the
  predicate must tell apart are tested in two files, deliberately, and each
  names the other. Change the predicate and run BOTH -- `testmgr --tier native
  --job src:test/test_generic_func.pas` is the one gate.sh quick does not
  cover. }
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
