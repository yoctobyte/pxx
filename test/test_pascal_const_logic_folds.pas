{ A CONSTANT LEFT OPERAND OF `and`/`or`, and `not` over a Boolean literal, must
  fold IN THE PARSER -- it is lowering, not an optimisation.

  Why it is not an optimisation: Pascal `and`/`or` short-circuit (this compiler
  has no {$BOOLEVAL}), so the right operand of `False and X` is not evaluated,
  and the language says so. What survived was the CODE for it, and that is not
  free: a call in the dead arm to a declared-but-never-defined external becomes
  a real reference and the binary dies before `main` with `undefined symbol`.

  MEASURED before the fix, at -O0, -O2 AND -O3 -- see test_pascal_dead_arm_ext
  below for the shape. Raising -O could not help, because the and/or lowering
  materialises its result in a boolean temp and the branch RELOADS it, so
  IROptConstBranch reads a load_sym and gives up.

  THIS FILE IS THE SEMANTICS HALF, and every row carries its HIT COUNT as well
  as its value, because a fold that drops an operand it should have kept still
  produces the right value for these shapes -- `True and T1` is True either way.
  The count is the only column that distinguishes folding from mis-folding.
  Rows that must NOT fold are here on purpose: `xor` does not short-circuit, so
  both operands run whatever the left one is; bitwise and/or/not on integers is
  a different operator wearing the same spelling; and a RUNTIME-false left
  operand short-circuits without being folded.

  Whole-file output verified byte-identical to fpc 3.2.2.
  feature-a-fold-the-consensus-dead-branch-core-at-every-level }
program test_pascal_const_logic_folds;
var hits: Integer;
function T1: Boolean; begin Inc(hits); T1 := True; end;
function F1: Boolean; begin Inc(hits); F1 := False; end;
procedure Show(const tag: string; b: Boolean; want: Boolean; wantHits, h: Integer);
begin
  Write(tag, ' val=', b, ' hits=', h);
  if (b = want) and (h = wantHits) then WriteLn(' ok') else WriteLn(' FAIL want=', want, '/', wantHits);
end;
var b: Boolean; i, j: Integer;
begin
  hits := 0; b := True and T1;   Show('True and T1 ', b, True,  1, hits);
  hits := 0; b := True and F1;   Show('True and F1 ', b, False, 1, hits);
  hits := 0; b := False and T1;  Show('False and T1', b, False, 0, hits);
  hits := 0; b := False or T1;   Show('False or T1 ', b, True,  1, hits);
  hits := 0; b := False or F1;   Show('False or F1 ', b, False, 1, hits);
  hits := 0; b := True or F1;    Show('True or F1  ', b, True,  0, hits);
  hits := 0; b := not True;      Show('not True    ', b, False, 0, hits);
  hits := 0; b := not False;     Show('not False   ', b, True,  0, hits);
  hits := 0; b := False xor T1;  Show('False xor T1', b, True,  1, hits);
  hits := 0; b := True xor T1;   Show('True xor T1 ', b, False, 1, hits);
  hits := 0; b := (False or False) or (not True);  Show('chain-false ', b, False, 0, hits);
  hits := 0; b := (False or False) or (not False); Show('chain-true  ', b, True,  0, hits);
  hits := 0; b := True and (True and T1);          Show('nested and  ', b, True,  1, hits);
  i := 12; j := 10;
  WriteLn('bitand=', i and j, ' want 8');
  WriteLn('bitor=', i or j, ' want 14');
  WriteLn('bitxor=', i xor j, ' want 6');
  WriteLn('notint=', not i, ' want -13');
  hits := 0; b := (1 > 2) and T1; Show('runtime-and ', b, False, 0, hits);
  WriteLn('CONSTLOGIC OK');
end.
