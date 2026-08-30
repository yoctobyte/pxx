program test_dead_loop_back_edge;
{ The same defect from the PASCAL frontend, because the fix is in the shared IR
  and a C-only test would not say so. Twin of c_dead_loop_back_edge.c, which
  diffs against gcc; this file is the frontend-independence half.

  `external name` on a symbol nothing defines is the load-bearing part: the
  reference reaches codegen only if the dead loop survives, and if it does the
  binary dies BEFORE the first WriteLn with `symbol lookup error`. Defining
  these deletes the test while leaving it green.

  FPC IS NOT THE ORACLE HERE, for the same reason its sibling records: fpc 3.2.2
  does not prune these either and fails to LINK. gcc does prune the equivalent
  C, and gcc is the oracle for the behaviour.

  What makes a loop different from the plain statement in d0 is that it is ITS
  OWN WITNESS: the only predecessor of the loop's top label is the loop's own
  back-jump, inside the region being decided. "Some jump names this label" is
  therefore always true, however many times you iterate. Only reachability from
  the ENTRY separates them.
  bug-a-a-loop-in-dead-code-keeps-itself-alive-through-its-own-back-edge }
function NEVER_while:  Integer; external name 'PXX_NEVER_DEFINED_dlbe_while';
function NEVER_repeat: Integer; external name 'PXX_NEVER_DEFINED_dlbe_repeat';
function NEVER_for:    Integer; external name 'PXX_NEVER_DEFINED_dlbe_for';
function NEVER_goto:   Integer; external name 'PXX_NEVER_DEFINED_dlbe_goto';

{ the shape that already worked -- the boundary row, here so the difference is
  visibly the loop and not the unreachability }
function d0(x: Integer): Integer;
begin d0 := x + 1; Exit; d0 := NEVER_while; end;

function d1(x: Integer): Integer;
begin d1 := x + 1; Exit; while True do d1 := NEVER_while; end;

function d2(x: Integer): Integer;
begin d2 := x + 1; Exit; repeat d2 := NEVER_repeat until False; end;

function d3(x: Integer): Integer;
var i: Integer;
begin d3 := x + 1; Exit; for i := 1 to 3 do d3 := NEVER_for; end;

{ A BACKWARD GOTO INTO A DEAD REGION -- the same self-witnessing shape wearing
  different syntax, and the reason this is one fix and not two: Lback is named
  only by a goto that is itself unreachable. Its live mirror is g1 in
  test_const_branch_dead_arm.pas, which must keep answering 1. }
function d4(x: Integer): Integer;
label Lback;
begin
  d4 := x + 1;
  Exit;
Lback:
  d4 := NEVER_goto;
  goto Lback;
end;

{ NEGATIVE CONTROLS. Reachability-from-entry deletes strictly more than the
  reference count it replaced, so the rows that matter most are the ones proving
  it stops in the right place -- pruning any of these is a miscompile, not a
  missed optimization. }
function l1(x: Integer): Integer;      { live infinite loop, left by Break }
var n: Integer;
begin n := 0; while True do begin n := n + x; if n > 40 then Break; end; l1 := n; end;

function l2(x: Integer): Integer;      { live loop whose back edge IS a goto }
label Lloop;
var n: Integer;
begin
  n := 0;
Lloop:
  n := n + 1;
  if n < x then goto Lloop;
  l2 := n;
end;

function l3(x: Integer): Integer;      { nested, with Continue and a case }
var n, i: Integer;
begin
  n := 0;
  for i := 1 to 6 do
  begin
    if i = 2 then Continue;
    case i of
      4: n := n + 10;
      5: n := n + 100;
    else n := n + 1;
    end;
    if n > 200 then Break;
  end;
  l3 := n + x;
end;

type
  EBoom = class(TObject) end;

function l4(x: Integer): Integer;      { an exception handler is a landing site }
begin
  l4 := 0;
  try
    if x > 0 then raise EBoom.Create;
    l4 := 1;
  except
    l4 := 2;
  end;
end;

begin
  WriteLn(d0(41), ' ', d1(41), ' ', d2(41), ' ', d3(41), ' ', d4(41));
  WriteLn(l1(7), ' ', l2(5), ' ', l3(0), ' ', l3(1), ' ', l4(0), ' ', l4(1));
end.
