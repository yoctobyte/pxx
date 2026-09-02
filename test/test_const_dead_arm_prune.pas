{ A CONSTANT CONDITION LOWERS THE DEAD ARM, at EVERY -O level -- `if` AND
  `while`, because they are one concept reached through two node kinds.

  gcc, clang and tcc all drop the dead arm, and tcc has no optimiser at all, so
  this is LOWERING and not an optimisation
  (decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0).
  IROptConstBranch already did it from -O1 up; that gate is correct and stays.
  -O0 was the level where `if False then Never()` still emitted the call, so the
  binary linked and died before main with `undefined symbol`.

  THE LABEL ROW IS THE GUARD'S POSITIVE CONTROL, and it is here rather than only
  in the C sibling because Pascal reaches the same hazard by a different route:
  `goto` into the arm. Measured with the guard disabled -- the compiler REFUSES
  the C computed-goto program outright ("invalid IR label-address target"), so
  the guard is load-bearing rather than decorative.

  FPC DISAGREES WITH THE LAST ROW AND THAT IS NOT A DEFECT. fpc 3.2.2 answers
  `Goto label "lbl" not defined or optimized away` -- it prunes the arm and
  loses a label a `goto` still targets. gcc, clang and tcc all KEEP such an arm,
  which is the consensus this work implements, and accepting what FPC rejects is
  explicitly not a defect here. Do not "fix" this row toward FPC. }
program test_const_dead_arm_prune;
label lbl, lbl2;
var n, jumped, w: Integer; s: string;
function Side(k: Integer): Integer; begin Inc(n, k); Side := k; end;
begin
  n := 0; jumped := 0;
  if False then Side(100);                       { no else: lowers to nothing }
  if True then Side(1) else Side(200);           { else pruned }
  if False then Side(300) else Side(2);          { then pruned, else kept }
  if True then begin Side(4); Side(8) end;       { compound live arm }
  if False then begin Side(400); Side(800) end;  { compound dead arm }
  { 1 + 2 + 4 + 8. Every pruned arm carries a side effect an order of magnitude
    larger, so a wrongly-KEPT arm does not merely slow this down -- it changes
    the number, and by how much says which arm leaked. }
  WriteLn('n=', n, ' want 15');
  { a managed temp in a live arm must still be built and finalized }
  if True then begin s := 'ab' + 'cd'; WriteLn('s=', s); end;
  { THE SIBLING SHAPE. `if` and `while` are one concept reached through two
    node kinds, and after the AN_IF prune landed this line still died at -O0
    with `undefined symbol` while the `if` above it was already fine. A test
    that stopped at `if` would have called the job done. }
  w := 0;
  while False do begin Side(1600); w := 99 end;
  { positive control for the TRUE side: `while True` is the desugaring target
    for Ada `loop` and several for-in shapes, so it must NOT be folded away.
    If a careless prune drops a constant-condition loop regardless of its
    value, this row stops running its body and w stays 0. }
  while True do begin w := w + 7; if w >= 7 then Break end;
  WriteLn('w=', w, ' want 7');

  { the guard: a label in a dead arm keeps it, and the goto must reach it }
  if False then begin lbl: jumped := 1; WriteLn('jumped in'); end;
  { and the same guard on the sibling: a dead `while` body holding a label is
    kept too, or the goto below has nowhere to land. }
  while False do begin lbl2: jumped := jumped + 1; end;
  if jumped = 0 then goto lbl;
  if jumped = 1 then goto lbl2;
  if jumped <> 2 then begin WriteLn('FAIL: jumped=', jumped, ' want 2'); Halt(1) end;
  WriteLn('DEADARMPRUNE OK');
end.
