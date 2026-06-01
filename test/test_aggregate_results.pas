program test_aggregate_results;

type
  TByteSet = set of Byte;
  TPair = record
    A, B: Integer;
  end;

function MakeLow: TByteSet;
begin
  Result := [1, 3];
end;

function MakeHigh: TByteSet;
begin
  Result := [8, 9];
end;

function MergeSets: TByteSet;
begin
  Result := MakeLow + MakeHigh;
end;

function ExitSet: TByteSet;
begin
  Exit([4, 6]);
end;

function MakePair(A, B: Integer): TPair;
begin
  Result.A := A;
  Result.B := B;
end;

function RecursivePair(N: Integer): TPair;
begin
  if N = 0 then
  begin
    Result := MakePair(10, 20);
    Exit;
  end;
  Result := RecursivePair(N - 1);
  Result.A := Result.A + N;
end;

var
  S: TByteSet;
  P: TPair;
begin
  S := MergeSets;
  if 1 in S then writeln(1) else writeln(0);
  if 3 in S then writeln(1) else writeln(0);
  if 8 in S then writeln(1) else writeln(0);
  if 9 in S then writeln(1) else writeln(0);
  S := ExitSet;
  if 4 in S then writeln(1) else writeln(0);
  if 6 in S then writeln(1) else writeln(0);
  P := MakePair(2, 5);
  writeln(P.A);
  writeln(P.B);
  P := RecursivePair(3);
  writeln(P.A);
  writeln(P.B);
end.
