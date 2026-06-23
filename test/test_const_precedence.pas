program test_const_precedence;
{ Constant expressions must respect operator precedence (multiplicative binds
  tighter than additive) and left-associativity, with unary minus binding
  tightest. Regression for bug-consteval-precedence (the old flat fold evaluated
  right-to-left, so 2*3+1 gave 8 not 7). Each line writes 1 for the FPC-correct
  value. }
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
end.
