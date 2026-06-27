program test_pointer_deref_depth;

type
  PInt = ^Integer;
  PPInt = ^PInt;
  PPPInt = ^PPInt;
  PPPPInt = ^PPPInt;
  PPair = ^TPair;
  PPPair = ^PPair;

  TPair = record
    A: Integer;
    B: Integer;
  end;

var
  X: Integer;
  P1: PInt;
  P2: PPInt;
  P3: PPPInt;
  P4: PPPPInt;
  Pair: TPair;
  PairP1: PPair;
  PairP2: PPPair;

begin
  X := 41;
  P1 := @X;
  P2 := @P1;
  P3 := @P2;
  P4 := @P3;

  P4^^^^ := P4^^^^ + 1;
  if X <> 42 then Halt(1);
  if P1^ <> 42 then Halt(2);
  if P2^^ <> 42 then Halt(3);
  if P3^^^ <> 42 then Halt(4);
  if P4^^^^ <> 42 then Halt(5);

  PairP1 := @Pair;
  PairP2 := @PairP1;
  PairP2^^.A := 11;
  PairP1^.B := 31;
  if PairP2^^.A + PairP2^^.B <> 42 then Halt(6);

  Halt(42);
end.
