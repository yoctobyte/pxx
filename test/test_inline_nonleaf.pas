{ Non-leaf inlining slice 1 (feature-inline-nonleaf-and-branch-locals, -O3):
  a body whose EXPRESSIONS contain direct calls to plain internal scalar
  functions retains and splices. When this test was written the inner calls
  stayed REAL calls and the win was only the removed outer frame; that stopped
  being true when depth-1 re-inline re-landed (d4c19919) and again when the
  budget became MAX_INLINE_DEPTH (2026-09-05), so at -O3 the inner calls now
  splice too. The assertions are unchanged and still correct: they are about
  side-effect count and order, which no depth may alter.
  Because a body-call may have side effects, the splice temp-captures
  EVERY argument (InlineBodyHasCall), preserving Pascal's evaluate-args-once
  order — g= below counts side effects exactly. Callees that write globals
  are NOT retained themselves (LHS is not Result/local) and stay as calls.
  Output must be identical at every -O level (optdiff sweeps this). }
program test_inline_nonleaf;

var gcount: Int64;

function Leaf(a: Int64): Int64;
begin
  Leaf := a * 3 + 1;
end;

function Effect(a: Int64): Int64;
begin
  gcount := gcount + 1;
  Effect := a + gcount;
end;

function Wrap(a, b: Int64): Int64;
begin
  Wrap := Leaf(a) + Leaf(b) * 2;
end;

function WrapEff(a: Int64): Int64;
begin
  WrapEff := Effect(a) * 10;
end;

function WrapBranch(a: Int64): Int64;
var t: Int64;
begin
  t := Leaf(a);
  if t > 100 then t := t - Leaf(a div 2);
  WrapBranch := t;
end;

var i, s, t, u: Int64;
begin
  gcount := 0; s := 0; t := 0; u := 0;
  for i := 1 to 100000 do
  begin
    s := s + Wrap(i and 63, i mod 17);
    t := t + WrapEff(i and 31);
    u := u + WrapBranch(i mod 90);
  end;
  writeln('s=', s);
  writeln('t=', t);
  writeln('u=', u);
  writeln('g=', gcount);
end.
