program test_o3_residency_six_hot_locals;
{ The -O3 loop-residency pass ranks a body's loop-hot scalars and parks the top
  few in callee-saved registers. The pool differs per backend — x86-64 uses
  r12..r15 (four), aarch64 x19..x24 (SIX) — but both passes index ONE set of
  parallel tables, and those tables were sized by x86-64's pool. So on aarch64
  the fifth and sixth resident wrote past the end of three arrays that sit
  adjacent in BSS, each overflow landing in the next.

  It presented as the compiler SEGFAULTING, and not on a program like this one:
  `--target=aarch64 -O3` died on `program n; begin end.`, because the units the
  empty program pulls in (builtinheap) contain bodies with four or more loop-hot
  scalars and are compiled before anything of the user's is.

  Six hot locals in one loop is therefore the shape that fills the pool. Every
  value is checked, not just the sum, so a resident that was assigned but never
  written back is caught as well as one that was never assigned.
  bug-a-aarch64-o3-segfaults-the-compiler-on-an-empty-program }
{$mode objfpc}{$H+}

function Hot: Integer;
var a, b, c, d, e, f, k, s: Integer;
begin
  a := 1; b := 2; c := 3; d := 4; e := 5; f := 6; s := 0;
  for k := 1 to 100 do
  begin
    s := s + a + b + c + d + e + f;
    a := a + 1; b := b + 2; c := c + 3; d := d + 4; e := e + 5; f := f + 6;
  end;
  Hot := s;
end;

procedure Tails(var oa, ob, oc, od, oe, of_: Integer);
var a, b, c, d, e, f, k: Integer;
begin
  a := 1; b := 2; c := 3; d := 4; e := 5; f := 6;
  for k := 1 to 100 do
  begin
    a := a + 1; b := b + 2; c := c + 3; d := d + 4; e := e + 5; f := f + 6;
  end;
  oa := a; ob := b; oc := c; od := d; oe := e; of_ := f;
end;

var a, b, c, d, e, f: Integer;
begin
  WriteLn('sum   ', Hot);
  Tails(a, b, c, d, e, f);
  WriteLn('tails ', a, ' ', b, ' ', c, ' ', d, ' ', e, ' ', f);
end.
