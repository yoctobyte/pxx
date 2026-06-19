{ A `; generator;` routine may yield a record element, consumed by `for x in`.
  The record does not fit the one-word "current" slot, so yield stores the
  record's ADDRESS (the stackful generator's frame keeps it alive until the next
  resume) and the for-in desugar derefs it into the loop variable. Closes Gap 3
  of feature-language-gaps-from-demos (chess movegen yields a TMove). Stackful
  (coroutine) path; x86-64. }
program test_generator_record;
uses coroutine;

type
  TMove = record fromSq, toSq, score: Int64; end;

function Moves(n: Integer): TMove; generator;
var i: Integer; m: TMove;
begin
  for i := 1 to n do
  begin
    m.fromSq := i;
    m.toSq   := i * 10;
    m.score  := i * i;
    yield m;
  end;
end;

var
  mv: TMove;
  s: Int64;
begin
  for mv in Moves(3) do
    Writeln(mv.fromSq, ' ', mv.toSq, ' ', mv.score);   { 1 10 1 / 2 20 4 / 3 30 9 }

  { sequential reuse + accumulation }
  s := 0;
  for mv in Moves(4) do s := s + mv.score;
  Writeln(s);                                          { 1+4+9+16 = 30 }
end.
