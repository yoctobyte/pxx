{ A `; generator;` routine may yield a record-returning CALL directly:
  `yield MkMove(...)`. The call result is non-addressable, so the compiler
  materialises it into a generator-frame local before yielding its address
  (the same lvalue path `tmp := MkMove(...)` uses). Regression for
  bug-generator-yield-call-expression (chess movegen). Stackful; x86-64. }
program test_generator_yield_call;
uses coroutine;

type
  TMove = record fromSq, toSq, kind: Int64; end;

function MkMove(f, t, k: Int64): TMove;
begin
  Result.fromSq := f;
  Result.toSq   := t;
  Result.kind   := k;
end;

function Moves: TMove; generator;
begin
  yield MkMove(1, 2, 10);
  yield MkMove(3, 4, 20);
  yield MkMove(5, 6, 30);
end;

var
  mv: TMove;
  s: Int64;
begin
  for mv in Moves do
    Writeln(mv.fromSq, ' ', mv.toSq, ' ', mv.kind);   { 1 2 10 / 3 4 20 / 5 6 30 }

  s := 0;
  for mv in Moves do s := s + mv.kind;
  Writeln(s);                                          { 10+20+30 = 60 }
end.
