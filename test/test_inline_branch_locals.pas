{ Inline slice 2c (feature-inline-nonleaf-and-branch-locals, -O3): bodies with
  branches + locals inline when definite-assignment holds on all paths.
  Shapes: a guard-if over a written local (no else); if/else both writing
  Result (definite via then-AND-else); a mixed chain reading entry-definite
  locals inside arms. A local written in only ONE arm stays non-definite —
  reading it after the if declines retention (correctness guard, not tested
  as a crash: the call path is the fallback). Bare-funcname-as-value bodies
  (`F := v; if F < lo ...`) do NOT retain (funcname in expr position is not a
  Result read in this dialect) — the call fallback keeps them correct.
  Output must be identical at every -O level (optdiff sweeps this). }
program test_inline_branch_locals;

function AbsDiff(a, b: Int64): Int64;
var d: Int64;
begin
  d := a - b;
  if d < 0 then d := -d;
  AbsDiff := d;
end;

function PickSign(x: Int64): Int64;
begin
  if x < 0 then PickSign := -1
  else PickSign := 1;
end;

function Clamp3(v, lo, hi: Int64): Int64;
var r: Int64;
begin
  r := v;
  if r < lo then r := lo;
  if r > hi then r := hi;
  Clamp3 := r;
end;

function Mix(a, b: Int64): Int64;
var lo, hi: Int64;
begin
  lo := a;
  hi := b;
  if lo > hi then Mix := lo - hi
  else Mix := hi - lo;
end;

var i, s, t, u, w: Int64;
begin
  s := 0; t := 0; u := 0; w := 0;
  for i := 1 to 500000 do
  begin
    s := s + Clamp3(i mod 300 - 100, 0, 99);
    t := t + AbsDiff(i and 255, 128);
    u := u + PickSign(i mod 7 - 3);
    w := w + Mix(i and 63, i mod 97);
  end;
  writeln('s=', s);
  writeln('t=', t);
  writeln('u=', u);
  writeln('w=', w);
end.
