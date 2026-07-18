{ Depth-1 re-inline reentrancy regression (feature-inline-nonleaf-and-branch-
  locals). The first depth-1 attempt (a3f6e70a, reverted) shared the
  InlineArgAST/InlineResultSym globals across nested IRInlineExpand
  activations: lowering a splice's ARGUMENT could re-enter the expander and
  rebind the outer call's argument ASTs mid-loop — nested calls in argument
  lists silently read the WRONG values at -O3 (fuzz-found, 21 repros, reduced
  to this shape). The fix binds into locals and publishes globals only inside
  the no-lowering clone window. This test nests retainable calls in argument
  lists (incl. inside case selectors and mixed with a side-effecting,
  unretainable callee) deep enough to exercise every reentry path.
  Output must be identical at every -O level (optdiff sweeps this). }
program test_inline_depth_reentry;

var
  cs: qword;
  gtick: Int64;

procedure Mix(v: Int64);
begin
  cs := qword(cs * 1000003) xor qword(v);
end;

function A(x: Int64): Int64;              { leaf }
begin
  A := x * 3 + 1;
end;

function B(x, y: Int64): Int64;           { 2c if/else }
begin
  if x > y then B := x - y
  else B := y - x + 1;
end;

function C(x: Int64): Int64;              { 2b chain with local }
var t: Int64;
begin
  t := x + 5;
  C := t * t;
end;

function Tick(x: Int64): Int64;           { side effects: never retained }
begin
  gtick := gtick + 1;
  Tick := x + gtick;
end;

var i, s: Int64;
begin
  cs := 7; gtick := 0; s := 0;
  for i := 1 to 50000 do
  begin
    { nested retainable calls in argument lists — the reentry shape }
    s := s + B(A(i and 63), C(i mod 17));
    Mix(B(B(i and 31, A(i mod 13)), A(B(i mod 7, 3))));
    { side-effecting callee mixed into nested args: order must hold exactly }
    Mix(A(B(Tick(i and 15), C(i mod 11))));
    { nested-call selector }
    case B(A(i and 3), C(i and 1)) and 3 of
      0: s := s + 1;
      1: s := s - 2;
    end;
  end;
  writeln('cs=', cs);
  writeln('s=', s);
  writeln('g=', gtick);
end.
