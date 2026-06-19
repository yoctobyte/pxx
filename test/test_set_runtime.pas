{ Sets built/mutated from runtime values: `[v]` and `[a..b]` with variable
  elements, plus Include(s, v) / Exclude(s, v). Constant set literals keep the
  baked fast path (last block). Closes Gap 1 of feature-language-gaps-from-demos
  (the sudoku candidate-set lane). Booleans print as 1/0. }
program test_set_runtime;

type
  TCand = set of 1..9;
  TByteSet = set of 0..255;

var
  cand: TCand;
  bs, bt: TByteSet;
  v, i: Integer;

begin
  { runtime single value + set union (the `s := s + [v]` sudoku idiom) }
  cand := [];
  v := 5; cand := cand + [v];
  v := 9; cand := cand + [v];
  Writeln(5 in cand, ' ', 9 in cand, ' ', 7 in cand);   { 1 1 0 }

  { Include / Exclude }
  Include(cand, 7);
  Writeln(7 in cand);                                    { 1 }
  Exclude(cand, 5);
  Writeln(5 in cand, ' ', 9 in cand);                    { 0 1 }

  { runtime range literal }
  i := 2;
  bt := [i .. i + 3];                                    { 2,3,4,5 }
  Writeln(1 in bt, ' ', 2 in bt, ' ', 5 in bt, ' ', 6 in bt);  { 0 1 1 0 }

  { mixed constant + runtime elements in one literal }
  v := 100;
  bs := [1, v, 200];
  Writeln(1 in bs, ' ', 100 in bs, ' ', 200 in bs, ' ', 50 in bs); { 1 1 1 0 }

  { all-constant literal still works (baked path) }
  cand := [1, 3, 5];
  Writeln(1 in cand, ' ', 2 in cand, ' ', 3 in cand);    { 1 0 1 }
end.
