{$mode objfpc}
program test_succ_pred_odd;

{ System ordinal intrinsics Succ / Pred / Odd, folded to arithmetic at parse
  time (no `uses`). FPC oracle: 6 4 / b / y / odd7 / even8 / 1. (Odd is used in
  if / Ord to avoid the separate writeln(Boolean) formatting issue.) }

var
  c: Char;
begin
  writeln(Succ(5), ' ', Pred(5));        { 6 4 }
  c := Succ('a'); writeln(c);            { b }
  c := Pred('z'); writeln(c);            { y }
  if Odd(7) then writeln('odd7');        { odd7 }
  if not Odd(8) then writeln('even8');   { even8 }
  writeln(Ord(Odd(9)));                  { 1 }
end.
