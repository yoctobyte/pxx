program test_ptr_arithmetic;

type
  TPoint = record
    X, Y: Integer;
  end;
  PInt64 = ^Int64;
  PPoint = ^TPoint;
  THolder = record
    P: PInt64;
  end;

var
  Values: array[0..3] of Int64;
  Points: array[0..2] of TPoint;
  P: PInt64;
  Q: PPoint;
  H: THolder;
begin
  Values[0] := 10;
  Values[1] := 20;
  Values[2] := 30;
  Values[3] := 40;

  P := @Values[0];
  P := P + 2;
  writeln(P^);
  P := P - 1;
  writeln(P^);
  P := 2 + P;
  writeln(P^);

  H.P := @Values[0];
  H.P := H.P + 3;
  writeln(H.P^);

  Points[1].X := 77;
  Points[2].X := 99;
  Q := @Points[0];
  Q := Q + 1;
  writeln(Q^.X);
  Q := Q + 1;
  writeln(Q^.X);

  P := PInt64(Pointer(@Values[0])) + 1;
  writeln(P^);
end.
