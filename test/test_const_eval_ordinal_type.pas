{ The constant evaluator must not erase an ordinal's TYPE.

  ConstEval represents every ordinal value -- char, enum, bool -- as a bare
  Int64. That is a real simplification and it is why Ord/Succ/Pred need no code
  at all. The cost was that the declaration site had no way to ask what kind
  came back, so it guessed from the FIRST TOKEN: right for a bare literal, wrong
  for every folded form. Measured against fpc 3.2.2 (-Mobjfpc -O1):

      const X = eB;      WriteLn(X)  fpc: eB   pxx: 1
      const Z = Low(TE); WriteLn(Z)  fpc: eA   pxx: 0
      const W = Low(TC); WriteLn(W)  fpc: a    pxx: 97

  `const Y = 'q'` was RIGHT, which is what made this look narrower than it is:
  the one-character-literal arm of ParseConstSection calls AddConst(tyChar) at
  that one site, so a char survived only when it was written as a literal.

  Every row here is pinned against fpc. The Ord rows are the guard on the other
  side: Ord is exactly the operator that DISCARDS the type, so `const N =
  Ord('a')` must stay 97 and must not inherit its operand's char-ness.
  bug-p-the-constant-evaluator-erases-an-ordinals-type }
program test_const_eval_ordinal_type;
type
  TE = (eA, eB, eC);
  TC = array['a'..'e'] of Integer;
  TEA = array[TE] of Integer;
  TDigit = 0..9;
  TLetter = 'a'..'e';
const
  { the four rows the ticket measured }
  X = eB;
  Y = 'q';
  Z = Low(TE);
  W = Low(TC);
  { the same folds at the other end }
  H = High(TC);
  HE = High(TE);
  ZEA = Low(TEA);
  HEA = High(TEA);
  { Ord DISCARDS the type; Succ/Pred KEEP it }
  N = Ord('a');
  M = Ord(eB);
  OW = Ord(Low(TC));
  S1 = Succ(eA);
  P1 = Pred(eC);
  SC = Succ('a');
  { Chr ADDS it }
  CH = Chr(65);
  { a named ordinal const keeps its kind when referenced }
  D = Y;
  E2 = X;
  { builtin ordinal type bounds }
  LC = Low(Char);
  HB = High(Boolean);
  LB = Low(Boolean);
  { named subranges: base-type kind, own bounds }
  LD = Low(TDigit);
  HD = High(TDigit);
  LL = Low(TLetter);
  HL = High(TLetter);
  { booleans still fold as booleans -- the behaviour this channel started as }
  F = 1 > 0;
  G = F and True;
  NF = not F;
  { ...and arithmetic over an ordinal is a NUMBER, not the ordinal }
  K = Ord('a') * 2;
  K2 = Ord(Low(TC)) + 1;
  { an integer typecast erases it too }
  IC = Integer(Ord('a'));
begin
  WriteLn(X); WriteLn(Y); WriteLn(Z); WriteLn(W);
  WriteLn(H); WriteLn(HE); WriteLn(ZEA); WriteLn(HEA);
  WriteLn(N); WriteLn(M); WriteLn(OW);
  WriteLn(S1); WriteLn(P1); WriteLn(SC);
  WriteLn(CH); WriteLn(D); WriteLn(E2);
  WriteLn(Ord(LC)); WriteLn(HB); WriteLn(LB);
  WriteLn(LD); WriteLn(HD); WriteLn(LL); WriteLn(HL);
  WriteLn(F); WriteLn(G); WriteLn(NF);
  WriteLn(K); WriteLn(K2); WriteLn(IC);
  { the consts must still behave as ordinals where one is wanted }
  WriteLn(Ord(X), ' ', Ord(W), ' ', Ord(Y));
  if W = 'a' then WriteLn('W=a') else WriteLn('W<>a');
  if X = eB then WriteLn('X=eB') else WriteLn('X<>eB');
  case W of 'a': WriteLn('case a'); else WriteLn('case other'); end;
end.
