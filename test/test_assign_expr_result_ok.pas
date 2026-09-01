{ The accept half of test_assign_expr_result_fail, and it RUNS: widening what
  the check can refuse widened what it can WRONGLY refuse by exactly as much.
  Numeric promotion is the row that matters -- AssignKindsIncompatible returns
  False for every int/float pair, so `d := i * 2` must survive untouched -- and
  a Char-valued expression assigned to a Char is the boundary row next to the
  six the fail file rejects. Output verified against fpc 3.2.2. }
program test_assign_expr_result_ok;
var d: Double; i: Integer; s: AnsiString; c: Char; b: Boolean;
begin
  i := 3; s := 'a'; c := 'q'; b := False;
  d := i * 2;          { int expression -> Double, must NOT be refused }
  i := i + 1;
  s := s + 'x';        { the ordinary concat }
  c := Chr(Ord(c));    { Char-valued expression -> Char }
  b := (i > 2) and not b;
  WriteLn(d:0:1, ' ', i, ' ', s, ' ', c, ' ', b);
end.
