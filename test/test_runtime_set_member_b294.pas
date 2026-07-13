{ A set constructor with a RUNTIME element, used with `in`:

      while not (FTokenStr^ in [#0, C]) do   { fcl-json's scanner; C is the active quote char }

  The `in` fast path folds every element to a constant and could not express this. But a set
  LITERAL already supports runtime elements, and `x in <set value>` already works as an
  ordinary binop -- so a runtime literal routes through those two, and the all-constant case
  keeps its baked-blob fast path untouched. That last part matters: the baked path is what the
  self-host binary depends on being byte-identical. }
program test_runtime_set_member_b294;
var
  c, q: Char;
  s: string;
  i: Integer;
begin
  q := '"';
  s := 'ab"cd';
  { a set with a RUNTIME member -- fcl-json's scanner: FTokenStr^ in [#0, C] }
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if c in [#0, q] then
      writeln(i, ': quote')
    else
      writeln(i, ': ', c);
  end;
  { the all-constant path must still work -- AND yield a BOOLEAN. It carried no type at all,
    so it defaulted to tyUnknown and printed 1/0, while the runtime path printed TRUE/FALSE:
    the same expression behaved differently depending on which path it took. Worse, an `and`
    of two of them was a BITWISE integer and, right only because the operands are 0/1. }
  writeln('const set: ', 'b' in ['a'..'c'], ' ', 'z' in ['a'..'c']);
end.
