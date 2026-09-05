{ Re-inline depth budget (feature-inline-nonleaf-and-branch-locals, -O3):
  MAX_INLINE_DEPTH lets a spliced body's inner calls re-inline more than one
  level, so a Top -> Mid -> Leaf chain collapses instead of leaving Leaf's calls
  real. Measured 2026-09-05: 1.92x on a 3-level wrapper loop, 1.13x on the
  raytracer.

  WHAT THIS TEST IS FOR, and it is not speed. Deeper nesting re-enters
  IRInlineExpand more times per call site, and that machinery was REVERTED once
  (819cb25a) after 21 silent -O3 divergences that every curated gate passed --
  the bug was argument binding through the SHARED InlineArgAST[] being rebound
  by an inner activation mid-loop. So the assertions here are about side-effect
  COUNT and ORDER through two splice levels, not about values alone: a value
  check cannot see an argument evaluated twice if the second evaluation happens
  to produce the same number.

  gcount counts side effects exactly. Output must be identical at every -O
  level; the -O0 column is the oracle. }
program test_inline_depth2;

var gcount: Int64;

function Leaf(a: Int64): Int64;
begin
  Leaf := a * 3 + 1;
end;

{ Writes a global, so it is NOT retained itself (LHS is neither Result nor a
  local) and stays a real call at every level. It is the side-effect probe. }
function Effect(a: Int64): Int64;
begin
  gcount := gcount + 1;
  Effect := a + gcount;
end;

function Mid(a: Int64): Int64;
begin
  Mid := Leaf(a) + Leaf(a + 1);
end;

{ Depth 2: Top splices into the caller, Mid splices inside Top, and Leaf's four
  calls splice inside the two Mid bodies. Under the old budget of 2 those four
  stayed real. }
function Top(a: Int64): Int64;
begin
  Top := Mid(a) + Mid(a + 2);
end;

{ The same shape with a side effect at the bottom. gcount must advance by
  exactly 2 per TopEff call, in argument order, however deeply the splice
  nests. }
function MidEff(a: Int64): Int64;
begin
  MidEff := Effect(a) * 10;
end;

function TopEff(a: Int64): Int64;
begin
  TopEff := MidEff(a) + MidEff(a + 1);
end;

{ Self-recursion is bounded ONLY by the budget -- there is no recursion guard by
  proc identity. A call at the budget lowers as a real call, so this must
  terminate and give the same answer at every level. If the budget ever stops
  being the termination proof, this hangs or blows the stack rather than
  printing a wrong number. }
function RecSum(n: Int64): Int64;
begin
  if n <= 0 then RecSum := 0 else RecSum := n + RecSum(n - 1);
end;

var i, s, e, r: Int64;
begin
  gcount := 0;
  s := 0;
  for i := 1 to 4 do s := s + Top(i);
  Writeln('Top      ', s);

  gcount := 0;
  e := 0;
  for i := 1 to 3 do e := e + TopEff(i);
  Writeln('TopEff   ', e);
  Writeln('gcount   ', gcount);

  r := RecSum(10);
  Writeln('RecSum   ', r);
end.
