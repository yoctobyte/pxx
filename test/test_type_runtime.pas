program TestTypeRuntime;

type
  TLayout = class
    A: Byte;
    B: Integer;
    C: Byte;
  end;

var
  U32A, U32B: LongWord;
  U64A, U64B: QWord;
  SignedValue: Integer;
  Signed64: Int64;
  Value: TLayout;

begin
  U32A := 4294967295;
  U32B := 1;
  if U32A > U32B then writeln(1) else writeln(0);

  U64A := -1;
  U64B := 1;
  if U64A > U64B then writeln(1) else writeln(0);

  SignedValue := -1;
  if SignedValue < U32B then writeln(1) else writeln(0);
  if SignedValue < U64B then writeln(1) else writeln(0);

  Signed64 := -1;
  if Signed64 < U64B then writeln(1) else writeln(0);

  writeln(U32A * U32A);
  writeln(U64A);
  U64B := 2;
  writeln(U64A div U64B);
  writeln(U64A mod U64B);
  SignedValue := -3;
  writeln(SignedValue div U64B);
  writeln(SignedValue mod U64B);
  U32B := 2;
  writeln(U32B + SignedValue);
  writeln(U64B + SignedValue);
  Signed64 := -3;
  writeln(U64B + Signed64);
  writeln(U64B div SignedValue);
  writeln(U64B mod SignedValue);

  Value := TLayout.Create;
  Value.A := 7;
  Value.B := 123456;
  Value.C := 9;
  writeln(Value.A);
  writeln(Value.B);
  writeln(Value.C);
  writeln(SizeOf(TLayout));
end.
