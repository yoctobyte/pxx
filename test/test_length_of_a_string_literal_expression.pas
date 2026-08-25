program test_length_of_a_string_literal_expression;
{ `Length('ab' + s)` was a PARSE ERROR while `Length(s + 'ab')` compiled.

  Length's compile-time fold for a string literal asked whether the argument
  STARTS with a literal and then demanded `)`. So a literal that was merely the
  LEFT operand of a concat was mistaken for the whole argument — one expression,
  three spellings, and only the one that happens to lead with the literal was
  refused. A fast path that is not a strict subset of the general one
  (devdocs/dev/normalise-dont-special-case.md).

  Both already-working spellings are asserted too, because the fix moves the
  refused one onto the ParseExpr path they already take, and the fold itself
  must keep working for a bare literal.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}{$H+}

function Suffix(k: Integer): AnsiString;
begin Result := 'xyz'; end;

var s: AnsiString; sh: string[10]; n: Integer;
begin
  s := 'q';
  sh := 'pq';
  { the refused spelling: a literal as the LEFT operand }
  WriteLn('litplus : ', Length('ab' + s));
  { …two literals, folded by neither side }
  WriteLn('litlit  : ', Length('ab' + 'cd'));
  { the spellings that always worked, on the same expression }
  WriteLn('varplus : ', Length(s + 'ab'));
  WriteLn('parens  : ', Length(('ab') + s));
  { the bare literal, which must still take the compile-time fold }
  WriteLn('bare    : ', Length('ab'));
  WriteLn('empty   : ', Length(''));
  { a literal leading a longer chain, and one over a call result }
  WriteLn('chain   : ', Length('ab' + s + 'cde'));
  WriteLn('call    : ', Length('ab' + Suffix(1)));
  { a frozen string on the right, and an ordinary variable }
  WriteLn('frozen  : ', Length('ab' + sh));
  WriteLn('plain   : ', Length(s));
  { the fold is a CONSTANT — usable where a constant is required }
  n := 0;
  case Length('abc') of
    3: n := 30;
  else n := -1;
  end;
  WriteLn('const   : ', n);
end.
