program test_variant_literal_concat_arg;
{ A literal-concat passed to a Variant parameter (Track A, found through NilPy:
  bug-nilpy-adjacent-string-literals-concatenate-in-only-some-positions).

  IR folds `'p' + 'q'` into ONE interned literal tagged tyString — deliberately,
  because a static literal pointer must never be treated as a heap handle. The
  AST node stays tyAnsiString, and the variant store took its source kind from
  the AST, so it boxed a literal AS a managed string and read a length word that
  is not there: `Show('p' + 'q')` handed over an EMPTY variant while `Show('pq')`
  and `s := 'p' + 'q'; Show(s)` were both correct. Silent, and reachable from
  plain Pascal.

  Every row here was correct BEFORE the fix except row 2 and row 6 — they are
  the ones that make this test worth keeping; the others are the known-good
  forms it must not disturb. }

var s: AnsiString; c: Char;

procedure Show(const v: Variant);
begin
  WriteLn('[', v, ']');
end;

function Echo(const v: Variant): Variant;
begin
  Echo := v;
end;

begin
  Show('pq');              { one literal — always worked }
  Show('p' + 'q');         { THE BUG: folded literal -> was empty }
  s := 'p' + 'q';
  Show(s);                 { via a managed local — always worked }
  c := 'x';
  Show(c + 'y');           { char + literal, not a two-literal fold }
  Show(s + 'r');
  Show(Echo('a' + 'b'));   { the fold through a Variant RESULT as well }
  WriteLn('direct: ', 'p' + 'q');
end.
