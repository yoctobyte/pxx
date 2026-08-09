program test_const_precedence;
{ Constant expressions must respect operator precedence (multiplicative binds
  tighter than additive) and left-associativity, with unary minus binding
  tightest. Regression for bug-consteval-precedence (the old flat fold evaluated
  right-to-left, so 2*3+1 gave 8 not 7). Each line writes 1 for the FPC-correct
  value.

  "Unary minus binding tightest" was ASSERTED here but not actually tested:
  every case above uses +, * or div, and for those `-(a op b)` and `(-a) op b`
  agree, so the file passed either way. `and` and `shr` are the operators that
  tell them apart, and pxx got them wrong — `-x and 12` was -(x and 12) = -8
  where FPC (and gcc, for the C frontend sharing this parser) says 8. Those rows
  are at the end, as constants AND as variables, since the two took different
  paths (both wrong). bug-a-unary-minus-binds-looser-than-and-shr }
const
  A = 2*3+1;        { 7 }
  B = 2+3*4+5;      { 19 }
  C = 100 div 10 + 5; { 15 }
  D = 20-4-3;       { 13 }
  E = 2 shl 1 + 1;  { 5 }
  F = -2+3;         { 1 }
  G = -2*3;         { -6 }
  H = -5;           { -5 }
  I = 1 shl 4 - 1;  { 15 }
  J = (2+3)*4;      { 20 }
  { the rows that actually pin the unary-minus binding }
  K = -8 and 12;    { (-8) and 12 = 8, not -(8 and 12) = -8 }
  L = -1 and 3;     { 3 }
  M = -8 or 1;      { -7 — or is additive-level, unchanged }
var vx: Integer;
procedure Chk(ok: Boolean);
begin if ok then writeln(1) else writeln(0); end;
begin
  Chk(A = 7);
  Chk(B = 19);
  Chk(C = 15);
  Chk(D = 13);
  Chk(E = 5);
  Chk(F = 1);
  Chk(G = -6);
  Chk(H = -5);
  Chk(I = 15);
  Chk(J = 20);
  Chk(K = 8);
  Chk(L = 3);
  Chk(M = -7);
  vx := 8;
  Chk((-vx and 12) = 8);
  { NOT asserted here: `-vx shr 1`. The binding is now right, but pxx shifts at
    the operand's 32 bits (2147483644) where FPC promotes to 64 first
    (9223372036854775804) — a WIDTH divergence with its own ticket,
    bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc. Asserting either
    answer here would bless one of them. }
  vx := 1;
  Chk((-vx and 3) = 3);
end.
